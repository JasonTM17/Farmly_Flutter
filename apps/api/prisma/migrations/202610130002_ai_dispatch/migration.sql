-- P09 AI dispatch surface: GUC-bound queue lease, lazy crash recovery,
-- snapshot/message writers and operator price lookup (spec05 §§3-6).
--
-- Every function is SECURITY DEFINER but actor-context bound: the caller must
-- present matching app.actor_id/app.actor_pseudonym GUCs, so the tenant role
-- can only ever touch its own rows. Global enumeration of other owners'
-- requests is impossible under the tenant role.

CREATE OR REPLACE FUNCTION public.farmly_ai_require_actor(
    p_actor_id TEXT,
    p_actor_pseudonym TEXT
) RETURNS VOID
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    IF p_actor_id IS NULL
       OR NULLIF(current_setting('app.actor_id', TRUE), '') IS DISTINCT FROM p_actor_id
       OR p_actor_pseudonym IS NULL
       OR NULLIF(current_setting('app.actor_pseudonym', TRUE), '') IS DISTINCT FROM p_actor_pseudonym THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'actor context mismatch';
    END IF;
END;
$$;

-- Operator-approved price snapshot lookup. The table itself stays closed to
-- the tenant role; pricing is public data but reads go through the definer so
-- the accounting surface stays narrow.
CREATE FUNCTION public.farmly_ai_price_snapshot(
    p_snapshot_id TEXT
) RETURNS TABLE (
    model TEXT,
    input_micros_per_mtok BIGINT,
    output_micros_per_mtok BIGINT,
    currency CHAR(3),
    captured_at TIMESTAMPTZ(6)
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
    SELECT model, input_micros_per_mtok, output_micros_per_mtok, currency, captured_at
      FROM public.ai_price_snapshots
     WHERE id = p_snapshot_id;
$$;

-- Owner-scoped queue lease (spec05 §4.1): returns only the caller's queued
-- request ids, oldest first. The fence remains the single CAS arbiter, so
-- callers racing over the same id can never double-dispatch.
CREATE FUNCTION public.farmly_ai_lease_queued(
    p_actor_id TEXT,
    p_actor_pseudonym TEXT,
    p_limit INTEGER DEFAULT 8
) RETURNS SETOF UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    PERFORM public.farmly_ai_require_actor(p_actor_id, p_actor_pseudonym);
    RETURN QUERY
    SELECT id FROM public.ai_requests
     WHERE actor_pseudonym = p_actor_pseudonym AND status = 'queued'
     ORDER BY created_at, id
     LIMIT GREATEST(1, LEAST(p_limit, 50));
END;
$$;

-- Lazy crash recovery (spec05 §4.4): a request whose attempt marker is older
-- than the stale bound can only belong to a dead executor — live dispatches
-- are bounded by the request timeout. Mark it interrupted with usage held
-- 'unknown' (conservative reservation retained, never a false zero-cost).
-- Called by the API whenever the owner acts (create/events/status), so
-- recovery needs no global worker and never crosses ownership.
CREATE FUNCTION public.farmly_ai_recover_interrupted(
    p_actor_id TEXT,
    p_actor_pseudonym TEXT,
    p_stale_seconds INTEGER
) RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    PERFORM public.farmly_ai_require_actor(p_actor_id, p_actor_pseudonym);
    WITH stale AS (
        UPDATE public.ai_requests
           SET status = 'interrupted', usage_state = 'unknown',
               terminal_at = CURRENT_TIMESTAMP,
               content_expires_at = CURRENT_TIMESTAMP + INTERVAL '24 hours',
               latest_seq = latest_seq + 1,
               updated_at = CURRENT_TIMESTAMP
         WHERE actor_pseudonym = p_actor_pseudonym
           AND status IN ('generating', 'stopping', 'dispatching')
           AND upstream_started_at IS NOT NULL
           AND upstream_started_at < CURRENT_TIMESTAMP - make_interval(secs => GREATEST(p_stale_seconds, 1))
        RETURNING id, latest_seq),
    events AS (
        INSERT INTO public.ai_events (request_id, seq, type, data)
        SELECT id, latest_seq, 'request.status',
               jsonb_build_object('status', 'interrupted', 'usageState', 'unknown')
          FROM stale),
    dec AS (
        UPDATE public.ai_org_counters counters
           SET in_flight = GREATEST(counters.in_flight - 1, 0)
          FROM stale
         WHERE counters.organization_id = (
               SELECT organization_id FROM public.ai_requests WHERE id = stale.id)
        RETURNING 1)
    SELECT count(*)::INT INTO v_count FROM stale;
    RETURN COALESCE(v_count, 0);
END;
$$;

-- Persist the serialized private context snapshot (spec05 §2): server-owned,
-- bound to the exact consent revision that authorized it. Only callable for
-- the caller's own farm-scoped request.
CREATE FUNCTION public.farmly_ai_write_snapshot(
    p_actor_id TEXT,
    p_actor_pseudonym TEXT,
    p_organization_id UUID,
    p_farm_id UUID,
    p_consent_revision INTEGER,
    p_schema_version TEXT,
    p_as_of TIMESTAMPTZ(6),
    p_payload JSONB,
    p_sources JSONB
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_id UUID;
BEGIN
    PERFORM public.farmly_ai_require_actor(p_actor_id, p_actor_pseudonym);
    IF NOT public.farmly_actor_can_read_farm(p_organization_id, p_farm_id) THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FARMLY_ACCESS_REVOKED';
    END IF;
    INSERT INTO public.ai_snapshots (
        organization_id, farm_id, user_id, actor_pseudonym, consent_revision,
        schema_version, as_of, payload, sources)
    VALUES (
        p_organization_id, p_farm_id, p_actor_id, p_actor_pseudonym, p_consent_revision,
        p_schema_version, p_as_of, p_payload, COALESCE(p_sources, '[]'::jsonb))
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;

-- Persist one owner-private message (assistant final, or service-side rows).
-- Sets the conversation completion marker used for the 30d retention clock.
CREATE FUNCTION public.farmly_ai_write_message(
    p_actor_id TEXT,
    p_actor_pseudonym TEXT,
    p_conversation_id UUID,
    p_role public.ai_message_role,
    p_body TEXT,
    p_request_id UUID
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_conversation public.ai_conversations%ROWTYPE;
    v_id UUID;
BEGIN
    PERFORM public.farmly_ai_require_actor(p_actor_id, p_actor_pseudonym);
    SELECT * INTO v_conversation FROM public.ai_conversations
     WHERE id = p_conversation_id AND actor_pseudonym = p_actor_pseudonym
       AND status = 'active';
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FARMLY_AI_CONVERSATION_UNKNOWN';
    END IF;
    INSERT INTO public.ai_messages (
        conversation_id, organization_id, farm_id, user_id, actor_pseudonym,
        role, body, request_id)
    VALUES (
        p_conversation_id, v_conversation.organization_id, v_conversation.farm_id,
        p_actor_id, p_actor_pseudonym, p_role, p_body, p_request_id)
    RETURNING id INTO v_id;
    IF p_role = 'assistant' THEN
        UPDATE public.ai_conversations
           SET latest_completed_at = CURRENT_TIMESTAMP
         WHERE id = p_conversation_id;
    END IF;
    RETURN v_id;
END;
$$;

-- Patched fence: identical semantics to 202610130001 plus the one persisted
-- terminal event on each cancelled path (spec05 §5 — every terminal state
-- carries exactly one terminal event).
CREATE OR REPLACE FUNCTION public.farmly_ai_dispatch_fence(
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
    PERFORM public.farmly_ai_require_actor(p_actor_id, p_actor_pseudonym);
    SELECT * INTO v_request FROM public.ai_requests
     WHERE id = p_request_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FARMLY_AI_REQUEST_UNKNOWN';
    END IF;

    IF v_request.status <> 'queued' OR v_request.upstream_started_at IS NOT NULL THEN
        RETURN jsonb_build_object('dispatched', FALSE, 'status', v_request.status);
    END IF;

    IF v_request.cancel_requested THEN
        UPDATE public.ai_requests
           SET status = 'cancelled', usage_state = 'notDispatched',
               terminal_at = CURRENT_TIMESTAMP,
               content_expires_at = CURRENT_TIMESTAMP + INTERVAL '24 hours',
               latest_seq = latest_seq + 1,
               updated_at = CURRENT_TIMESTAMP
         WHERE id = p_request_id;
        INSERT INTO public.ai_events (request_id, seq, type, data)
        VALUES (p_request_id, v_request.latest_seq + 1, 'response.cancelled',
                jsonb_build_object('partial', FALSE, 'usageState', 'notDispatched'));
        UPDATE public.ai_org_counters
           SET reserved_output_tokens = reserved_output_tokens - v_request.reserved_output_tokens,
               in_flight = GREATEST(in_flight - 1, 0)
         WHERE organization_id = v_request.organization_id;
        UPDATE public.ai_project_counters
           SET reserved_cost_micros = reserved_cost_micros - v_request.reserved_cost_micros
         WHERE singleton;
        RETURN jsonb_build_object('dispatched', FALSE, 'status', 'cancelled');
    END IF;

    SELECT * INTO v_consent FROM public.ai_consents
     WHERE organization_id = v_request.organization_id AND user_id = v_request.user_id;
    IF NOT FOUND OR NOT v_consent.granted
       OR v_consent.revision <> v_request.consent_revision THEN
        UPDATE public.ai_requests
           SET status = 'cancelled', usage_state = 'notDispatched',
               terminal_at = CURRENT_TIMESTAMP,
               content_expires_at = CURRENT_TIMESTAMP + INTERVAL '24 hours',
               latest_seq = latest_seq + 1,
               updated_at = CURRENT_TIMESTAMP
         WHERE id = p_request_id;
        INSERT INTO public.ai_events (request_id, seq, type, data)
        VALUES (p_request_id, v_request.latest_seq + 1, 'response.cancelled',
                jsonb_build_object('partial', FALSE, 'usageState', 'notDispatched',
                                   'reason', 'consent'));
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

REVOKE ALL ON FUNCTION public.farmly_ai_require_actor(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.farmly_ai_price_snapshot(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.farmly_ai_lease_queued(TEXT, TEXT, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.farmly_ai_recover_interrupted(TEXT, TEXT, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.farmly_ai_write_snapshot(TEXT, TEXT, UUID, UUID, INTEGER, TEXT, TIMESTAMPTZ(6), JSONB, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.farmly_ai_write_message(TEXT, TEXT, UUID, public.ai_message_role, TEXT, UUID) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.farmly_ai_price_snapshot(TEXT) TO farmly_tenant_app;
GRANT EXECUTE ON FUNCTION public.farmly_ai_lease_queued(TEXT, TEXT, INTEGER) TO farmly_tenant_app;
GRANT EXECUTE ON FUNCTION public.farmly_ai_recover_interrupted(TEXT, TEXT, INTEGER) TO farmly_tenant_app;
GRANT EXECUTE ON FUNCTION public.farmly_ai_write_snapshot(TEXT, TEXT, UUID, UUID, INTEGER, TEXT, TIMESTAMPTZ(6), JSONB, JSONB) TO farmly_tenant_app;
GRANT EXECUTE ON FUNCTION public.farmly_ai_write_message(TEXT, TEXT, UUID, public.ai_message_role, TEXT, UUID) TO farmly_tenant_app;
-- farmly_ai_require_actor is internal plumbing for the definer surface.
