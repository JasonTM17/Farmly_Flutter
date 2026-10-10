-- P09 AI core: private conversations, durable requests, persisted events,
-- consent ledger, quota counters and price snapshots (spec05 §§2-6).
--
-- Every AI table is private-owner-only: RLS binds rows to the caller's
-- actor_pseudonym carried in the `app.actor_pseudonym` GUC (set alongside
-- app.actor_id by the service in every AI transaction). Tenant roles get
-- SELECT only; all writes run through SECURITY DEFINER functions so the
-- dispatch fence, reservation accounting and terminal CAS stay atomic.

CREATE TYPE public.ai_context_mode AS ENUM ('authorized-summary', 'none');
CREATE TYPE public.ai_request_status AS ENUM
    ('queued', 'dispatching', 'generating', 'stopping', 'completed', 'cancelled', 'interrupted', 'error');
CREATE TYPE public.ai_usage_state AS ENUM
    ('notDispatched', 'reserved', 'reported', 'estimated', 'unknown', 'pessimisticallySettled', 'reconciled');
CREATE TYPE public.ai_event_type AS ENUM
    ('request.started', 'response.delta', 'request.status', 'response.references',
     'usage.reported', 'response.completed', 'response.cancelled', 'response.error');
CREATE TYPE public.ai_conversation_status AS ENUM ('active', 'archived', 'deleted');
CREATE TYPE public.ai_message_role AS ENUM ('user', 'assistant');

-- ------------------------------------------------------------------ consent
-- One row per (org, user): the current AI context consent revision. The
-- `ai_safe_summary_opted_in` flag gates the separately-authorized
-- aiSafeOperationalSummary field (spec05 §2 R1 — default no free-text egress).
CREATE TABLE public.ai_consents (
    organization_id UUID NOT NULL,
    user_id TEXT NOT NULL,
    actor_pseudonym CHAR(64) NOT NULL CHECK (actor_pseudonym ~ '^[a-f0-9]{64}$'),
    revision INTEGER NOT NULL DEFAULT 1 CHECK (revision >= 1),
    granted BOOLEAN NOT NULL,
    ai_safe_summary_opted_in BOOLEAN NOT NULL DEFAULT FALSE,
    granted_at TIMESTAMPTZ(6),
    withdrawn_at TIMESTAMPTZ(6),
    updated_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ai_consents_pkey PRIMARY KEY (organization_id, user_id),
    CONSTRAINT ai_consents_organization_fkey FOREIGN KEY (organization_id)
        REFERENCES public.organizations(id) ON DELETE CASCADE,
    CONSTRAINT ai_consents_user_fkey FOREIGN KEY (user_id)
        REFERENCES auth."user"(id) ON DELETE RESTRICT
);

-- -------------------------------------------------------------- conversation
CREATE TABLE public.ai_conversations (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL,
    farm_id UUID NOT NULL,
    user_id TEXT NOT NULL,
    actor_pseudonym CHAR(64) NOT NULL CHECK (actor_pseudonym ~ '^[a-f0-9]{64}$'),
    title VARCHAR(200),
    status public.ai_conversation_status NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    latest_completed_at TIMESTAMPTZ(6),
    CONSTRAINT ai_conversations_pkey PRIMARY KEY (id),
    CONSTRAINT ai_conversations_org_id_key UNIQUE (organization_id, id),
    CONSTRAINT ai_conversations_organization_fkey FOREIGN KEY (organization_id)
        REFERENCES public.organizations(id) ON DELETE CASCADE,
    CONSTRAINT ai_conversations_farm_fkey FOREIGN KEY (organization_id, farm_id)
        REFERENCES public.farms(organization_id, id) ON DELETE CASCADE,
    CONSTRAINT ai_conversations_user_fkey FOREIGN KEY (user_id)
        REFERENCES auth."user"(id) ON DELETE RESTRICT
);
CREATE INDEX ai_conversations_owner_idx
    ON public.ai_conversations(actor_pseudonym, organization_id, farm_id, created_at DESC);

CREATE TABLE public.ai_messages (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL,
    organization_id UUID NOT NULL,
    farm_id UUID NOT NULL,
    user_id TEXT NOT NULL,
    actor_pseudonym CHAR(64) NOT NULL CHECK (actor_pseudonym ~ '^[a-f0-9]{64}$'),
    role public.ai_message_role NOT NULL,
    body TEXT NOT NULL CHECK (length(body) BETWEEN 1 AND 12000),
    request_id UUID,
    created_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ai_messages_pkey PRIMARY KEY (id),
    CONSTRAINT ai_messages_conversation_id_key UNIQUE (conversation_id, id),
    CONSTRAINT ai_messages_conversation_fkey FOREIGN KEY (conversation_id)
        REFERENCES public.ai_conversations(id) ON DELETE CASCADE
);
CREATE INDEX ai_messages_conversation_idx
    ON public.ai_messages(conversation_id, created_at, id);

-- ------------------------------------------------------------- context snapshot
-- Server-owned private context snapshot (spec05 §2): allowlisted facts only,
-- bound to the consent revision that authorized it.
CREATE TABLE public.ai_snapshots (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL,
    farm_id UUID NOT NULL,
    user_id TEXT NOT NULL,
    actor_pseudonym CHAR(64) NOT NULL CHECK (actor_pseudonym ~ '^[a-f0-9]{64}$'),
    consent_revision INTEGER NOT NULL CHECK (consent_revision >= 1),
    schema_version TEXT NOT NULL,
    as_of TIMESTAMPTZ(6) NOT NULL,
    payload JSONB NOT NULL,
    sources JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ai_snapshots_pkey PRIMARY KEY (id)
);

-- ------------------------------------------------------------------- requests
CREATE TABLE public.ai_requests (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL,
    farm_id UUID NOT NULL,
    conversation_id UUID NOT NULL,
    user_id TEXT NOT NULL,
    actor_pseudonym CHAR(64) NOT NULL CHECK (actor_pseudonym ~ '^[a-f0-9]{64}$'),
    client_request_id UUID NOT NULL,
    -- sha256 over the canonical create payload; same key + different bytes = 409.
    request_hash CHAR(64) NOT NULL,
    consent_revision INTEGER NOT NULL CHECK (consent_revision >= 1),
    context_mode public.ai_context_mode NOT NULL,
    -- prompt + user message are purged by the 24h content TTL after terminal.
    prompt TEXT,
    prompt_bytes INTEGER NOT NULL,
    snapshot_id UUID,
    status public.ai_request_status NOT NULL DEFAULT 'queued',
    cancel_requested BOOLEAN NOT NULL DEFAULT FALSE,
    -- Dispatch fence: the attempt marker is committed inside the fence tx
    -- BEFORE any provider byte is sent; a crash after it is 'interrupted'
    -- forever — recovery never re-dispatches (spec05 §4).
    attempt_id UUID,
    upstream_started_at TIMESTAMPTZ(6),
    fence_version INTEGER NOT NULL DEFAULT 1 CHECK (fence_version >= 1),
    latest_seq BIGINT NOT NULL DEFAULT 0 CHECK (latest_seq >= 0),
    final_message_id UUID,
    finish_reason TEXT CHECK (finish_reason IS NULL OR finish_reason IN ('stop', 'length')),
    truncated BOOLEAN,
    usage_state public.ai_usage_state NOT NULL DEFAULT 'reserved',
    input_tokens INTEGER CHECK (input_tokens IS NULL OR input_tokens >= 0),
    output_tokens INTEGER CHECK (output_tokens IS NULL OR output_tokens >= 0),
    total_tokens INTEGER CHECK (total_tokens IS NULL OR total_tokens >= 0),
    reserved_output_tokens INTEGER NOT NULL CHECK (reserved_output_tokens >= 0),
    reserved_input_bytes BIGINT NOT NULL CHECK (reserved_input_bytes >= 0),
    -- Reserved/expected cost as integer micro-currency — never float.
    reserved_cost_micros BIGINT NOT NULL CHECK (reserved_cost_micros >= 0),
    reported_cost_micros BIGINT CHECK (reported_cost_micros IS NULL OR reported_cost_micros >= 0),
    error_code TEXT,
    terminal_at TIMESTAMPTZ(6),
    content_expires_at TIMESTAMPTZ(6),
    content_purged_at TIMESTAMPTZ(6),
    created_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ai_requests_pkey PRIMARY KEY (id),
    CONSTRAINT ai_requests_org_id_key UNIQUE (organization_id, id),
    CONSTRAINT ai_requests_owner_client_key UNIQUE (organization_id, user_id, client_request_id),
    CONSTRAINT ai_requests_organization_fkey FOREIGN KEY (organization_id)
        REFERENCES public.organizations(id) ON DELETE CASCADE,
    CONSTRAINT ai_requests_farm_fkey FOREIGN KEY (organization_id, farm_id)
        REFERENCES public.farms(organization_id, id) ON DELETE CASCADE,
    CONSTRAINT ai_requests_conversation_fkey FOREIGN KEY (conversation_id)
        REFERENCES public.ai_conversations(id) ON DELETE CASCADE,
    CONSTRAINT ai_requests_user_fkey FOREIGN KEY (user_id)
        REFERENCES auth."user"(id) ON DELETE RESTRICT,
    CONSTRAINT ai_requests_terminal_coherence CHECK (
        (terminal_at IS NULL) = (status IN ('queued', 'dispatching', 'generating', 'stopping'))
        AND (finish_reason IS NOT NULL OR status <> 'completed')
        AND (truncated IS NULL OR status IN ('completed', 'cancelled'))
    )
);
CREATE INDEX ai_requests_owner_idx
    ON public.ai_requests(actor_pseudonym, organization_id, farm_id, created_at DESC);
CREATE INDEX ai_requests_queued_idx ON public.ai_requests(status)
    WHERE status IN ('queued', 'dispatching', 'generating', 'stopping');

-- --------------------------------------------------------------------- events
-- Persisted-before-emission event log; seq is server-monotonic per request.
CREATE TABLE public.ai_events (
    request_id UUID NOT NULL,
    seq BIGINT NOT NULL CHECK (seq >= 1),
    type public.ai_event_type NOT NULL,
    data JSONB NOT NULL,
    created_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    event_id TEXT GENERATED ALWAYS AS (request_id::TEXT || ':' || seq::TEXT) STORED,
    CONSTRAINT ai_events_pkey PRIMARY KEY (request_id, seq),
    CONSTRAINT ai_events_request_fkey FOREIGN KEY (request_id)
        REFERENCES public.ai_requests(id) ON DELETE CASCADE
);

-- -------------------------------------------------------------------- quota
-- Atomic counters — rows are locked in the reservation transaction, so two
-- concurrent creates at the last slot cannot both dispatch (FAI-22).
CREATE TABLE public.ai_org_counters (
    organization_id UUID PRIMARY KEY REFERENCES public.organizations(id) ON DELETE CASCADE,
    reserved_output_tokens BIGINT NOT NULL DEFAULT 0 CHECK (reserved_output_tokens >= 0),
    reported_tokens BIGINT NOT NULL DEFAULT 0 CHECK (reported_tokens >= 0),
    in_flight INTEGER NOT NULL DEFAULT 0 CHECK (in_flight >= 0)
);

CREATE TABLE public.ai_project_counters (
    singleton BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (singleton),
    reserved_cost_micros BIGINT NOT NULL DEFAULT 0 CHECK (reserved_cost_micros >= 0),
    reported_cost_micros BIGINT NOT NULL DEFAULT 0 CHECK (reported_cost_micros >= 0)
);
INSERT INTO public.ai_project_counters (singleton) VALUES (TRUE);

-- Operator-approved model pricing (spec05 §6): integer micro-units per
-- million tokens + revision/time/currency provenance. Never float math.
CREATE TABLE public.ai_price_snapshots (
    id TEXT PRIMARY KEY,
    model TEXT NOT NULL,
    input_micros_per_mtok BIGINT NOT NULL CHECK (input_micros_per_mtok >= 0),
    output_micros_per_mtok BIGINT NOT NULL CHECK (output_micros_per_mtok >= 0),
    currency CHAR(3) NOT NULL DEFAULT 'USD',
    captured_at TIMESTAMPTZ(6) NOT NULL
);

-- ======================================================================= RLS
ALTER TABLE public.ai_consents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_consents FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ai_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_conversations FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ai_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_messages FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ai_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_snapshots FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ai_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_requests FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ai_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_events FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ai_org_counters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_org_counters FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ai_project_counters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_project_counters FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ai_price_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_price_snapshots FORCE ROW LEVEL SECURITY;

CREATE POLICY ai_consents_migration_access ON public.ai_consents
    TO farmly_migration USING (TRUE) WITH CHECK (TRUE);
CREATE POLICY ai_conversations_migration_access ON public.ai_conversations
    TO farmly_migration USING (TRUE) WITH CHECK (TRUE);
CREATE POLICY ai_messages_migration_access ON public.ai_messages
    TO farmly_migration USING (TRUE) WITH CHECK (TRUE);
CREATE POLICY ai_snapshots_migration_access ON public.ai_snapshots
    TO farmly_migration USING (TRUE) WITH CHECK (TRUE);
CREATE POLICY ai_requests_migration_access ON public.ai_requests
    TO farmly_migration USING (TRUE) WITH CHECK (TRUE);
CREATE POLICY ai_events_migration_access ON public.ai_events
    TO farmly_migration USING (TRUE) WITH CHECK (TRUE);
CREATE POLICY ai_org_counters_migration_access ON public.ai_org_counters
    TO farmly_migration USING (TRUE) WITH CHECK (TRUE);
CREATE POLICY ai_project_counters_migration_access ON public.ai_project_counters
    TO farmly_migration USING (TRUE) WITH CHECK (TRUE);
CREATE POLICY ai_price_snapshots_migration_access ON public.ai_price_snapshots
    TO farmly_migration USING (TRUE) WITH CHECK (TRUE);

-- Private-owner reads: the row's owner pseudonym must equal the caller's.
CREATE POLICY ai_consents_owner_read ON public.ai_consents
    FOR SELECT TO farmly_tenant_app
    USING (actor_pseudonym = NULLIF(current_setting('app.actor_pseudonym', TRUE), ''));
CREATE POLICY ai_conversations_owner_read ON public.ai_conversations
    FOR SELECT TO farmly_tenant_app
    USING (actor_pseudonym = NULLIF(current_setting('app.actor_pseudonym', TRUE), '')
           AND status <> 'deleted');
CREATE POLICY ai_messages_owner_read ON public.ai_messages
    FOR SELECT TO farmly_tenant_app
    USING (actor_pseudonym = NULLIF(current_setting('app.actor_pseudonym', TRUE), ''));
CREATE POLICY ai_snapshots_owner_read ON public.ai_snapshots
    FOR SELECT TO farmly_tenant_app
    USING (actor_pseudonym = NULLIF(current_setting('app.actor_pseudonym', TRUE), ''));
CREATE POLICY ai_requests_owner_read ON public.ai_requests
    FOR SELECT TO farmly_tenant_app
    USING (actor_pseudonym = NULLIF(current_setting('app.actor_pseudonym', TRUE), ''));
CREATE POLICY ai_events_owner_read ON public.ai_events
    FOR SELECT TO farmly_tenant_app
    USING (EXISTS (
        SELECT 1 FROM public.ai_requests r
        WHERE r.id = request_id
          AND r.actor_pseudonym = NULLIF(current_setting('app.actor_pseudonym', TRUE), '')
    ));

REVOKE ALL ON TABLE public.ai_consents, public.ai_conversations, public.ai_messages,
    public.ai_snapshots, public.ai_requests, public.ai_events,
    public.ai_org_counters, public.ai_project_counters, public.ai_price_snapshots
    FROM PUBLIC, farmly_auth_app, farmly_tenant_app;
GRANT SELECT ON TABLE public.ai_consents, public.ai_conversations, public.ai_messages,
    public.ai_snapshots, public.ai_requests, public.ai_events
    TO farmly_tenant_app;
-- Counters/price snapshots are operator-internal; the tenant role never reads
-- or writes them directly (definer functions handle accounting).

-- ============================================================ definer surface

-- Create or replay one private AI request. Atomic: consent recheck, rate/quota
-- reservation and the request row land in one definer call so a concurrent
-- create at the last slot fails closed instead of double-dispatching.
CREATE FUNCTION public.farmly_ai_create_request(
    p_actor_id TEXT,
    p_actor_pseudonym TEXT,
    p_organization_id UUID,
    p_farm_id UUID,
    p_conversation_id UUID,
    p_client_request_id UUID,
    p_request_hash CHAR(64),
    p_prompt TEXT,
    p_context_mode public.ai_context_mode,
    p_consent_revision INTEGER,
    p_reserved_output_tokens INTEGER,
    p_reserved_input_bytes BIGINT,
    p_reserved_cost_micros BIGINT,
    p_user_rate_limit INTEGER,
    p_org_token_cap BIGINT,
    p_project_cost_cap_micros BIGINT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_conversation public.ai_conversations%ROWTYPE;
    v_request public.ai_requests%ROWTYPE;
    v_existing public.ai_requests%ROWTYPE;
    v_in_flight BIGINT;
BEGIN
    IF p_actor_id IS NULL
       OR NULLIF(current_setting('app.actor_id', TRUE), '') IS DISTINCT FROM p_actor_id
       OR p_actor_pseudonym IS NULL
       OR NULLIF(current_setting('app.actor_pseudonym', TRUE), '') IS DISTINCT FROM p_actor_pseudonym THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'actor context mismatch';
    END IF;

    -- Farm read grant is the AI authorization floor (read-only AI surface).
    IF NOT public.farmly_actor_can_read_farm(p_organization_id, p_farm_id) THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FARMLY_ACCESS_REVOKED';
    END IF;

    -- Current consent must be granted and match the client's revision claim.
    PERFORM 1 FROM public.ai_consents
     WHERE organization_id = p_organization_id AND user_id = p_actor_id
       AND granted AND revision = p_consent_revision;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FARMLY_AI_CONSENT_REQUIRED';
    END IF;

    -- Idempotency: same client key replays only on byte-identical payloads.
    SELECT * INTO v_existing FROM public.ai_requests
     WHERE organization_id = p_organization_id AND user_id = p_actor_id
       AND client_request_id = p_client_request_id;
    IF FOUND THEN
        IF v_existing.request_hash <> p_request_hash THEN
            RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'FARMLY_AI_REQUEST_MISMATCH';
        END IF;
        RETURN jsonb_build_object(
            'requestId', v_existing.id,
            'conversationId', v_existing.conversation_id,
            'status', v_existing.status,
            'replayed', TRUE,
            'contentPurged', v_existing.content_purged_at IS NOT NULL);
    END IF;

    -- Conversation: create on demand or rebind an existing private one.
    IF p_conversation_id IS NULL THEN
        INSERT INTO public.ai_conversations (organization_id, farm_id, user_id, actor_pseudonym)
        VALUES (p_organization_id, p_farm_id, p_actor_id, p_actor_pseudonym)
        RETURNING * INTO v_conversation;
    ELSE
        SELECT * INTO v_conversation FROM public.ai_conversations
         WHERE id = p_conversation_id AND organization_id = p_organization_id
           AND farm_id = p_farm_id AND actor_pseudonym = p_actor_pseudonym
           AND status = 'active';
        IF NOT FOUND THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FARMLY_AI_CONVERSATION_UNKNOWN';
        END IF;
    END IF;

    -- Per-user rate gate: count of non-terminal requests owned by the caller.
    SELECT count(*) INTO v_in_flight FROM public.ai_requests
     WHERE organization_id = p_organization_id AND user_id = p_actor_id
       AND terminal_at IS NULL;
    IF p_user_rate_limit IS NOT NULL AND v_in_flight >= p_user_rate_limit THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FARMLY_AI_RATE_LIMITED';
    END IF;

    -- Atomic quota reservation: org token cap + project cost cap under row locks.
    INSERT INTO public.ai_org_counters (organization_id)
    VALUES (p_organization_id)
    ON CONFLICT (organization_id) DO NOTHING;
    PERFORM 1 FROM public.ai_org_counters
     WHERE organization_id = p_organization_id FOR UPDATE;
    PERFORM 1 FROM public.ai_project_counters WHERE singleton FOR UPDATE;

    IF p_org_token_cap IS NOT NULL THEN
        PERFORM 1 FROM public.ai_org_counters
         WHERE organization_id = p_organization_id
           AND reported_tokens + reserved_output_tokens + p_reserved_output_tokens
               <= p_org_token_cap;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FARMLY_AI_ORG_CAP';
        END IF;
    END IF;
    IF p_project_cost_cap_micros IS NOT NULL THEN
        PERFORM 1 FROM public.ai_project_counters
         WHERE singleton
           AND reported_cost_micros + reserved_cost_micros + p_reserved_cost_micros
               <= p_project_cost_cap_micros;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FARMLY_AI_PROJECT_CAP';
        END IF;
    END IF;

    UPDATE public.ai_org_counters
       SET reserved_output_tokens = reserved_output_tokens + p_reserved_output_tokens,
           in_flight = in_flight + 1
     WHERE organization_id = p_organization_id;
    UPDATE public.ai_project_counters
       SET reserved_cost_micros = reserved_cost_micros + p_reserved_cost_micros
     WHERE singleton;

    INSERT INTO public.ai_requests (
        organization_id, farm_id, conversation_id, user_id, actor_pseudonym,
        client_request_id, request_hash, consent_revision, context_mode,
        prompt, prompt_bytes, reserved_output_tokens, reserved_input_bytes,
        reserved_cost_micros)
    VALUES (
        p_organization_id, p_farm_id, v_conversation.id, p_actor_id, p_actor_pseudonym,
        p_client_request_id, p_request_hash, p_consent_revision, p_context_mode,
        p_prompt, length(p_prompt::BYTEA), p_reserved_output_tokens, p_reserved_input_bytes,
        p_reserved_cost_micros)
    RETURNING * INTO v_request;

    INSERT INTO public.ai_messages (
        conversation_id, organization_id, farm_id, user_id, actor_pseudonym,
        role, body, request_id)
    VALUES (
        v_conversation.id, p_organization_id, p_farm_id, p_actor_id, p_actor_pseudonym,
        'user', p_prompt, v_request.id);

    RETURN jsonb_build_object(
        'requestId', v_request.id,
        'conversationId', v_conversation.id,
        'status', v_request.status,
        'replayed', FALSE,
        'contentPurged', FALSE);
END;
$$;

-- Dispatch fence (spec05 §4): inside one transaction, re-verify ownership,
-- grant, current consent and cancel flag; then persist the attempt marker
-- BEFORE any upstream byte. A cancelled-with-no-marker request releases its
-- reservation and is provably 'notDispatched'.
CREATE FUNCTION public.farmly_ai_dispatch_fence(
    p_actor_id TEXT,
    p_actor_pseudonym TEXT,
    p_request_id UUID,
    p_attempt_id UUID
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_request public.ai_requests%ROWTYPE;
    v_consent public.ai_consents%ROWTYPE;
BEGIN
    SELECT * INTO v_request FROM public.ai_requests
     WHERE id = p_request_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FARMLY_AI_REQUEST_UNKNOWN';
    END IF;

    -- Already dispatched or terminal: fence refuses a second attempt marker.
    IF v_request.status <> 'queued' OR v_request.upstream_started_at IS NOT NULL THEN
        RETURN jsonb_build_object('dispatched', FALSE, 'status', v_request.status);
    END IF;

    -- Withdrawal serialized inside the fence: queued + cancelled now means the
    -- reservation is released and no provider attempt ever exists.
    IF v_request.cancel_requested THEN
        UPDATE public.ai_requests
           SET status = 'cancelled', usage_state = 'notDispatched',
               terminal_at = CURRENT_TIMESTAMP,
               content_expires_at = CURRENT_TIMESTAMP + INTERVAL '24 hours',
               updated_at = CURRENT_TIMESTAMP
         WHERE id = p_request_id;
        UPDATE public.ai_org_counters
           SET reserved_output_tokens = reserved_output_tokens - v_request.reserved_output_tokens,
               in_flight = GREATEST(in_flight - 1, 0)
         WHERE organization_id = v_request.organization_id;
        UPDATE public.ai_project_counters
           SET reserved_cost_micros = reserved_cost_micros - v_request.reserved_cost_micros
         WHERE singleton;
        RETURN jsonb_build_object('dispatched', FALSE, 'status', 'cancelled');
    END IF;

    -- Live consent recheck at fence time — a withdrawal since create blocks
    -- dispatch (spec05 §2: queued-not-dispatched must not call upstream).
    SELECT * INTO v_consent FROM public.ai_consents
     WHERE organization_id = v_request.organization_id AND user_id = v_request.user_id;
    IF NOT FOUND OR NOT v_consent.granted
       OR v_consent.revision <> v_request.consent_revision THEN
        UPDATE public.ai_requests
           SET status = 'cancelled', usage_state = 'notDispatched',
               terminal_at = CURRENT_TIMESTAMP,
               content_expires_at = CURRENT_TIMESTAMP + INTERVAL '24 hours',
               updated_at = CURRENT_TIMESTAMP
         WHERE id = p_request_id;
        UPDATE public.ai_org_counters
           SET reserved_output_tokens = reserved_output_tokens - v_request.reserved_output_tokens,
               in_flight = GREATEST(in_flight - 1, 0)
         WHERE organization_id = v_request.organization_id;
        UPDATE public.ai_project_counters
           SET reserved_cost_micros = reserved_cost_micros - v_request.reserved_cost_micros
         WHERE singleton;
        RETURN jsonb_build_object('dispatched', FALSE, 'status', 'cancelled', 'reason', 'consent');
    END IF;

    UPDATE public.ai_requests
       SET status = 'generating',
           attempt_id = p_attempt_id,
           upstream_started_at = CURRENT_TIMESTAMP,
           fence_version = fence_version + 1,
           updated_at = CURRENT_TIMESTAMP
     WHERE id = p_request_id;

    RETURN jsonb_build_object(
        'dispatched', TRUE,
        'status', 'generating',
        'requestId', v_request.id,
        'organizationId', v_request.organization_id,
        'farmId', v_request.farm_id,
        'conversationId', v_request.conversation_id,
        'snapshotId', v_request.snapshot_id,
        'contextMode', v_request.context_mode,
        'consentRevision', v_request.consent_revision,
        'prompt', v_request.prompt,
        'reservedOutputTokens', v_request.reserved_output_tokens,
        'fenceVersion', v_request.fence_version + 1);
END;
$$;

-- Append a batch of persisted events; returns the new latest_seq. Terminal
-- events are enforced by farmly_ai_terminalize, not here.
CREATE FUNCTION public.farmly_ai_append_events(
    p_request_id UUID,
    p_events JSONB
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_next BIGINT;
BEGIN
    UPDATE public.ai_requests
       SET latest_seq = latest_seq + jsonb_array_length(p_events),
           updated_at = CURRENT_TIMESTAMP
     WHERE id = p_request_id
    RETURNING latest_seq INTO v_next;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FARMLY_AI_REQUEST_UNKNOWN';
    END IF;
    INSERT INTO public.ai_events (request_id, seq, type, data)
    SELECT p_request_id,
           v_next - jsonb_array_length(p_events) + (ordinality::BIGINT),
           (item->>'type')::public.ai_event_type,
           item->'data'
      FROM jsonb_array_elements(p_events) WITH ORDINALITY AS e(item, ordinality);
    RETURN v_next;
END;
$$;

-- Single terminal transition: CAS from a live status, settle the reservation
-- (reported/estimated usage reconciles reserved→reported; unknown keeps the
-- conservative reservation per spec05 §6 — never TTL-refunded), persist the
-- one terminal event, and mark content expiry (24h) for the purge job.
CREATE FUNCTION public.farmly_ai_terminalize(
    p_request_id UUID,
    p_terminal_status public.ai_request_status,
    p_usage_state public.ai_usage_state,
    p_event_type public.ai_event_type,
    p_event_data JSONB,
    p_input_tokens INTEGER DEFAULT NULL,
    p_output_tokens INTEGER DEFAULT NULL,
    p_total_tokens INTEGER DEFAULT NULL,
    p_reported_cost_micros BIGINT DEFAULT NULL,
    p_final_message_id UUID DEFAULT NULL,
    p_finish_reason TEXT DEFAULT NULL,
    p_truncated BOOLEAN DEFAULT NULL,
    p_error_code TEXT DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_request public.ai_requests%ROWTYPE;
    v_seq BIGINT;
BEGIN
    SELECT * INTO v_request FROM public.ai_requests
     WHERE id = p_request_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FARMLY_AI_REQUEST_UNKNOWN';
    END IF;
    -- Exactly one terminal state/event: CAS refuses any second terminal.
    IF v_request.status NOT IN ('queued', 'dispatching', 'generating', 'stopping') THEN
        RETURN FALSE;
    END IF;

    UPDATE public.ai_requests
       SET status = p_terminal_status,
           usage_state = p_usage_state,
           input_tokens = p_input_tokens,
           output_tokens = p_output_tokens,
           total_tokens = p_total_tokens,
           reported_cost_micros = p_reported_cost_micros,
           final_message_id = p_final_message_id,
           finish_reason = p_finish_reason,
           truncated = p_truncated,
           error_code = p_error_code,
           terminal_at = CURRENT_TIMESTAMP,
           content_expires_at = CURRENT_TIMESTAMP + INTERVAL '24 hours',
           updated_at = CURRENT_TIMESTAMP
     WHERE id = p_request_id;

    -- Reservation settlement (spec05 §6):
    --   notDispatched → release fully (no upstream attempt ever existed);
    --   reported/estimated/reconciled → convert reservation to reported actuals;
    --   unknown/pessimisticallySettled → HOLD the reservation (conservative
    --   cap consumption; no TTL auto-refund, actualCost stays NULL).
    UPDATE public.ai_org_counters
       SET reserved_output_tokens = reserved_output_tokens
               - CASE WHEN p_usage_state = 'notDispatched'
                       OR p_usage_state IN ('reported', 'estimated', 'reconciled')
                      THEN v_request.reserved_output_tokens ELSE 0 END,
           reported_tokens = reported_tokens + COALESCE(p_output_tokens, 0),
           in_flight = GREATEST(in_flight - 1, 0)
     WHERE organization_id = v_request.organization_id;
    UPDATE public.ai_project_counters
       SET reserved_cost_micros = reserved_cost_micros
               - CASE WHEN p_usage_state = 'notDispatched'
                       OR p_usage_state IN ('reported', 'estimated', 'reconciled')
                      THEN v_request.reserved_cost_micros ELSE 0 END,
           reported_cost_micros = reported_cost_micros + COALESCE(p_reported_cost_micros, 0)
     WHERE singleton;

    v_seq := v_request.latest_seq + 1;
    INSERT INTO public.ai_events (request_id, seq, type, data)
    VALUES (p_request_id, v_seq, p_event_type, p_event_data);
    UPDATE public.ai_requests SET latest_seq = v_seq WHERE id = p_request_id;
    RETURN TRUE;
END;
$$;

-- Owner-private cancel: queued/dispatching → cancelled+notDispatched
-- (reservation released); generating/stopping → cancel_requested flag the
-- dispatcher observes between batches; terminal → idempotent current state.
CREATE FUNCTION public.farmly_ai_cancel_request(
    p_actor_id TEXT,
    p_actor_pseudonym TEXT,
    p_request_id UUID
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_request public.ai_requests%ROWTYPE;
BEGIN
    IF p_actor_id IS NULL
       OR NULLIF(current_setting('app.actor_id', TRUE), '') IS DISTINCT FROM p_actor_id
       OR p_actor_pseudonym IS NULL
       OR NULLIF(current_setting('app.actor_pseudonym', TRUE), '') IS DISTINCT FROM p_actor_pseudonym THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'actor context mismatch';
    END IF;

    SELECT * INTO v_request FROM public.ai_requests
     WHERE id = p_request_id AND actor_pseudonym = p_actor_pseudonym
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FARMLY_AI_REQUEST_UNKNOWN';
    END IF;

    IF v_request.status IN ('queued', 'dispatching') THEN
        UPDATE public.ai_requests
           SET status = 'cancelled', usage_state = 'notDispatched',
               terminal_at = CURRENT_TIMESTAMP,
               content_expires_at = CURRENT_TIMESTAMP + INTERVAL '24 hours',
               updated_at = CURRENT_TIMESTAMP
         WHERE id = p_request_id;
        UPDATE public.ai_org_counters
           SET reserved_output_tokens = reserved_output_tokens - v_request.reserved_output_tokens,
               in_flight = GREATEST(in_flight - 1, 0)
         WHERE organization_id = v_request.organization_id;
        UPDATE public.ai_project_counters
           SET reserved_cost_micros = reserved_cost_micros - v_request.reserved_cost_micros
         WHERE singleton;
        INSERT INTO public.ai_events (request_id, seq, type, data)
        VALUES (p_request_id, v_request.latest_seq + 1, 'response.cancelled',
                jsonb_build_object('partial', FALSE, 'usageState', 'notDispatched'));
        UPDATE public.ai_requests SET latest_seq = latest_seq + 1 WHERE id = p_request_id;
        RETURN jsonb_build_object('status', 'cancelled', 'dispatched', FALSE);
    END IF;

    IF v_request.status IN ('generating', 'stopping') THEN
        UPDATE public.ai_requests
           SET cancel_requested = TRUE, status = 'stopping', updated_at = CURRENT_TIMESTAMP
         WHERE id = p_request_id;
        RETURN jsonb_build_object('status', 'stopping', 'dispatched', TRUE);
    END IF;

    RETURN jsonb_build_object('status', v_request.status, 'dispatched', v_request.attempt_id IS NOT NULL);
END;
$$;

-- Consent grant/withdrawal (the P10 privacy UI calls these; tests seed via
-- migration role). Withdrawal bumps the revision so any queued request fails
-- its fence recheck; generating requests get cancel_requested (post-marker
-- abort is best-effort per spec05 §2).
CREATE FUNCTION public.farmly_ai_set_consent(
    p_actor_id TEXT,
    p_actor_pseudonym TEXT,
    p_organization_id UUID,
    p_granted BOOLEAN,
    p_ai_safe_summary_opted_in BOOLEAN DEFAULT FALSE
) RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_revision INTEGER;
    v_purge_rows INTEGER;
BEGIN
    IF p_actor_id IS NULL
       OR NULLIF(current_setting('app.actor_id', TRUE), '') IS DISTINCT FROM p_actor_id
       OR p_actor_pseudonym IS NULL
       OR NULLIF(current_setting('app.actor_pseudonym', TRUE), '') IS DISTINCT FROM p_actor_pseudonym THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'actor context mismatch';
    END IF;
    INSERT INTO public.ai_consents (
        organization_id, user_id, actor_pseudonym, revision, granted,
        ai_safe_summary_opted_in, granted_at, withdrawn_at, updated_at)
    VALUES (
        p_organization_id, p_actor_id, p_actor_pseudonym, 1, p_granted,
        p_ai_safe_summary_opted_in,
        CASE WHEN p_granted THEN CURRENT_TIMESTAMP END,
        CASE WHEN p_granted THEN NULL ELSE CURRENT_TIMESTAMP END,
        CURRENT_TIMESTAMP)
    ON CONFLICT (organization_id, user_id) DO UPDATE
       SET revision = ai_consents.revision + 1,
           granted = EXCLUDED.granted,
           ai_safe_summary_opted_in = EXCLUDED.ai_safe_summary_opted_in,
           granted_at = CASE WHEN EXCLUDED.granted THEN CURRENT_TIMESTAMP END,
           withdrawn_at = CASE WHEN EXCLUDED.granted THEN NULL ELSE CURRENT_TIMESTAMP END,
           updated_at = CURRENT_TIMESTAMP
    RETURNING revision INTO v_revision;

    IF NOT p_granted THEN
        -- Cancel exactly the rows this withdrawal transitions: the `stale`
        -- CTE's RETURNING set drives both the cancelled event and the
        -- reservation release, so a repeated withdrawal is a no-op.
        WITH stale AS (
            UPDATE public.ai_requests
               SET status = 'cancelled', usage_state = 'notDispatched',
                   terminal_at = CURRENT_TIMESTAMP,
                   content_expires_at = CURRENT_TIMESTAMP + INTERVAL '24 hours',
                   latest_seq = latest_seq + 1,
                   updated_at = CURRENT_TIMESTAMP
             WHERE organization_id = p_organization_id AND user_id = p_actor_id
               AND status IN ('queued', 'dispatching')
               AND upstream_started_at IS NULL
            RETURNING id, latest_seq, reserved_output_tokens, reserved_cost_micros),
        events AS (
            INSERT INTO public.ai_events (request_id, seq, type, data)
            SELECT id, latest_seq, 'response.cancelled',
                   jsonb_build_object('partial', FALSE, 'usageState', 'notDispatched')
              FROM stale),
        released AS (
            SELECT count(*)::INTEGER AS count,
                   COALESCE(sum(reserved_output_tokens), 0)::BIGINT AS tokens,
                   COALESCE(sum(reserved_cost_micros), 0)::BIGINT AS micros
              FROM stale),
        org_release AS (
            UPDATE public.ai_org_counters counters
               SET reserved_output_tokens = counters.reserved_output_tokens - released.tokens,
                   in_flight = GREATEST(counters.in_flight - released.count, 0)
              FROM released
             WHERE counters.organization_id = p_organization_id
            RETURNING 1),
        project_release AS (
            UPDATE public.ai_project_counters
               SET reserved_cost_micros = reserved_cost_micros - released.micros
              FROM released
             WHERE singleton
            RETURNING 1)
        SELECT count(*)::INT FROM org_release, project_release INTO v_purge_rows;
        -- Post-marker requests: flag the abort; the dispatcher suppresses
        -- further output and records usage unknown (never "free").
        UPDATE public.ai_requests
           SET cancel_requested = TRUE,
               status = CASE WHEN status = 'generating' THEN 'stopping' ELSE status END,
               updated_at = CURRENT_TIMESTAMP
         WHERE organization_id = p_organization_id AND user_id = p_actor_id
           AND status IN ('generating', 'stopping');
    END IF;
    RETURN v_revision;
END;
$$;

-- Content TTL purge (migration-role maintenance): prompt/user-message content
-- expires 24h after terminal; events share the same TTL; conversation
-- retention is 30d from latest completed response. Purged content never
-- admits the request as a new paid call — the proof row survives.
CREATE FUNCTION public.farmly_ai_purge_expired_content()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_count INTEGER := 0;
BEGIN
    WITH purged AS (
        UPDATE public.ai_requests
           SET prompt = NULL, content_purged_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
         WHERE terminal_at IS NOT NULL
           AND content_expires_at IS NOT NULL
           AND content_expires_at <= CURRENT_TIMESTAMP
           AND content_purged_at IS NULL
        RETURNING id, conversation_id)
    UPDATE public.ai_messages message
       SET body = '[content expired]'
      FROM purged
     WHERE message.request_id = purged.id AND message.role = 'user';
    GET DIAGNOSTICS v_count = ROW_COUNT;

    DELETE FROM public.ai_events event
     USING public.ai_requests request
     WHERE event.request_id = request.id
       AND request.content_purged_at IS NOT NULL;

    RETURN v_count;
END;
$$;

-- Bind the serialized context snapshot and re-verify the fence generation
-- immediately before the provider call (spec05 §4.4): if the fence was lost
-- or cancel raced in, the bind refuses and the dispatcher must not call.
CREATE FUNCTION public.farmly_ai_bind_snapshot(
    p_request_id UUID,
    p_snapshot_id UUID,
    p_expected_fence_version INTEGER
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_bound BOOLEAN;
BEGIN
    UPDATE public.ai_requests
       SET snapshot_id = p_snapshot_id, updated_at = CURRENT_TIMESTAMP
     WHERE id = p_request_id
       AND status = 'generating'
       AND NOT cancel_requested
       AND fence_version = p_expected_fence_version
       AND upstream_started_at IS NOT NULL
    RETURNING TRUE INTO v_bound;
    RETURN COALESCE(v_bound, FALSE);
END;
$$;

REVOKE ALL ON FUNCTION public.farmly_ai_create_request(TEXT, TEXT, UUID, UUID, UUID, UUID, CHAR(64), TEXT, public.ai_context_mode, INTEGER, INTEGER, BIGINT, BIGINT, INTEGER, BIGINT, BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.farmly_ai_dispatch_fence(TEXT, TEXT, UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.farmly_ai_append_events(UUID, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.farmly_ai_terminalize(UUID, public.ai_request_status, public.ai_usage_state, public.ai_event_type, JSONB, INTEGER, INTEGER, INTEGER, BIGINT, UUID, TEXT, BOOLEAN, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.farmly_ai_cancel_request(TEXT, TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.farmly_ai_bind_snapshot(UUID, UUID, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.farmly_ai_set_consent(TEXT, TEXT, UUID, BOOLEAN, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.farmly_ai_purge_expired_content() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.farmly_ai_create_request(TEXT, TEXT, UUID, UUID, UUID, UUID, CHAR(64), TEXT, public.ai_context_mode, INTEGER, INTEGER, BIGINT, BIGINT, INTEGER, BIGINT, BIGINT) TO farmly_tenant_app;
GRANT EXECUTE ON FUNCTION public.farmly_ai_dispatch_fence(TEXT, TEXT, UUID, UUID) TO farmly_tenant_app;
GRANT EXECUTE ON FUNCTION public.farmly_ai_append_events(UUID, JSONB) TO farmly_tenant_app;
GRANT EXECUTE ON FUNCTION public.farmly_ai_terminalize(UUID, public.ai_request_status, public.ai_usage_state, public.ai_event_type, JSONB, INTEGER, INTEGER, INTEGER, BIGINT, UUID, TEXT, BOOLEAN, TEXT) TO farmly_tenant_app;
GRANT EXECUTE ON FUNCTION public.farmly_ai_cancel_request(TEXT, TEXT, UUID) TO farmly_tenant_app;
GRANT EXECUTE ON FUNCTION public.farmly_ai_bind_snapshot(UUID, UUID, INTEGER) TO farmly_tenant_app;
GRANT EXECUTE ON FUNCTION public.farmly_ai_set_consent(TEXT, TEXT, UUID, BOOLEAN, BOOLEAN) TO farmly_tenant_app;
GRANT EXECUTE ON FUNCTION public.farmly_ai_purge_expired_content() TO farmly_migration;

-- The fence/terminal functions run nested authorization helpers.
GRANT EXECUTE ON FUNCTION public.farmly_actor_can_read_farm(UUID, UUID) TO farmly_migration;
