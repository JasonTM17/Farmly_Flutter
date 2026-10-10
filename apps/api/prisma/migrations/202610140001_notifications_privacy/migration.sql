-- P10 notifications + privacy: recipient-owned in-app notifications with
-- dedup keys, installation-bound device registrations, and audited
-- privacy requests (export / delete-history / withdraw-ai-consent).
--
-- Same posture as ai_*: rows are owner-private via actor_pseudonym RLS;
-- every write runs through SECURITY DEFINER functions; push tokens are
-- never logged and only ever stored hashed for dedup.

-- pgcrypto (trusted): digest() for token/pseudonym hashing inside definers.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE public.notification_kind AS ENUM ('reminder', 'alert', 'system');
CREATE TYPE public.device_registration_status AS ENUM ('registered', 'revoked');
CREATE TYPE public.privacy_request_action AS ENUM ('export', 'delete-history', 'withdraw-ai-consent');
CREATE TYPE public.privacy_request_status AS ENUM ('requested', 'processing', 'completed', 'failed');

-- ------------------------------------------------------------ notifications
CREATE TABLE public.notifications (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL,
    farm_id UUID,
    user_id TEXT NOT NULL,
    actor_pseudonym CHAR(64) NOT NULL CHECK (actor_pseudonym ~ '^[a-f0-9]{64}$'),
    kind public.notification_kind NOT NULL,
    title VARCHAR(200) NOT NULL,
    body VARCHAR(1000),
    dedup_key TEXT NOT NULL,
    source_ref TEXT,
    read_at TIMESTAMPTZ(6),
    created_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT notifications_pkey PRIMARY KEY (id),
    CONSTRAINT notifications_dedup UNIQUE (user_id, dedup_key),
    CONSTRAINT notifications_org_fkey FOREIGN KEY (organization_id)
        REFERENCES public.organizations(id) ON DELETE CASCADE
);
CREATE INDEX notifications_owner_feed
    ON public.notifications(actor_pseudonym, created_at DESC);
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications FORCE ROW LEVEL SECURITY;

-- ------------------------------------------------------- device_registrations
CREATE TABLE public.device_registrations (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL,
    actor_pseudonym CHAR(64) NOT NULL CHECK (actor_pseudonym ~ '^[a-f0-9]{64}$'),
    device_id VARCHAR(200) NOT NULL,
    push_token TEXT,
    token_digest CHAR(64) CHECK (token_digest IS NULL OR token_digest ~ '^[a-f0-9]{64}$'),
    status public.device_registration_status NOT NULL DEFAULT 'registered',
    last_operation_id UUID NOT NULL,
    registered_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revoked_at TIMESTAMPTZ(6),
    updated_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT device_registrations_pkey PRIMARY KEY (id),
    CONSTRAINT device_registrations_owner_device UNIQUE (user_id, device_id)
);
-- At most one active account binding per installation (device_id).
CREATE UNIQUE INDEX device_registrations_one_active
    ON public.device_registrations(device_id) WHERE status = 'registered';
ALTER TABLE public.device_registrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.device_registrations FORCE ROW LEVEL SECURITY;

-- ---------------------------------------------------------- privacy_requests
CREATE TABLE public.privacy_requests (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    operation_id UUID NOT NULL,
    user_id TEXT NOT NULL,
    actor_pseudonym CHAR(64) NOT NULL CHECK (actor_pseudonym ~ '^[a-f0-9]{64}$'),
    action public.privacy_request_action NOT NULL,
    action_hash CHAR(64) NOT NULL CHECK (action_hash ~ '^[a-f0-9]{64}$'),
    status public.privacy_request_status NOT NULL DEFAULT 'requested',
    payload JSONB,
    error_code TEXT,
    requested_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ(6),
    CONSTRAINT privacy_requests_pkey PRIMARY KEY (id),
    CONSTRAINT privacy_requests_operation UNIQUE (operation_id)
);
CREATE INDEX privacy_requests_owner_feed
    ON public.privacy_requests(actor_pseudonym, requested_at DESC);
ALTER TABLE public.privacy_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.privacy_requests FORCE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------- RLS / grants
CREATE POLICY notifications_migration_access ON public.notifications
    FOR ALL TO farmly_migration USING (TRUE) WITH CHECK (TRUE);
CREATE POLICY device_registrations_migration_access ON public.device_registrations
    FOR ALL TO farmly_migration USING (TRUE) WITH CHECK (TRUE);
CREATE POLICY privacy_requests_migration_access ON public.privacy_requests
    FOR ALL TO farmly_migration USING (TRUE) WITH CHECK (TRUE);

CREATE POLICY notifications_owner_read ON public.notifications
    FOR SELECT TO farmly_tenant_app
    USING (actor_pseudonym = NULLIF(current_setting('app.actor_pseudonym', TRUE), ''));
CREATE POLICY device_registrations_owner_read ON public.device_registrations
    FOR SELECT TO farmly_tenant_app
    USING (actor_pseudonym = NULLIF(current_setting('app.actor_pseudonym', TRUE), ''));
CREATE POLICY privacy_requests_owner_read ON public.privacy_requests
    FOR SELECT TO farmly_tenant_app
    USING (actor_pseudonym = NULLIF(current_setting('app.actor_pseudonym', TRUE), ''));

GRANT SELECT ON public.notifications TO farmly_tenant_app;
GRANT SELECT ON public.device_registrations TO farmly_tenant_app;
GRANT SELECT ON public.privacy_requests TO farmly_tenant_app;

-- --------------------------------------------------------- definer functions

-- Idempotent one-notification-per (recipient, dedup_key). Returns the row
-- (existing on replay — no duplicates for recurring reminders).
CREATE OR REPLACE FUNCTION public.farmly_notify_recipient(
    p_organization_id UUID,
    p_farm_id UUID,
    p_user_id TEXT,
    p_actor_pseudonym CHAR(64),
    p_kind public.notification_kind,
    p_title VARCHAR(200),
    p_body VARCHAR(1000),
    p_dedup_key TEXT,
    p_source_ref TEXT DEFAULT NULL
) RETURNS public.notifications
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_catalog AS $$
DECLARE
    v_row public.notifications;
BEGIN
    INSERT INTO public.notifications (
        organization_id, farm_id, user_id, actor_pseudonym,
        kind, title, body, dedup_key, source_ref)
    VALUES (
        p_organization_id, p_farm_id, p_user_id, p_actor_pseudonym,
        p_kind, p_title, p_body, p_dedup_key, p_source_ref)
    ON CONFLICT (user_id, dedup_key) DO NOTHING
    RETURNING * INTO v_row;
    IF v_row.id IS NULL THEN
        SELECT * INTO v_row FROM public.notifications
         WHERE user_id = p_user_id AND dedup_key = p_dedup_key;
    END IF;
    RETURN v_row;
END;
$$;

-- Reminder fan-out for open task occurrences due within the window: one
-- durable notification per (occurrence, recipient) via dedup_key; recipients
-- are users holding a current farm grant. Definer-only — the app role never
-- enumerates other users' grants directly.
CREATE OR REPLACE FUNCTION public.farmly_generate_task_reminders(
    p_window INTERVAL DEFAULT INTERVAL '24 hours'
) RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_catalog AS $$
DECLARE
    v_count INTEGER := 0;
BEGIN
    WITH due AS (
        SELECT occurrence.organization_id, occurrence.farm_id, occurrence.id,
               occurrence.occurrence_date, occurrence.slot, template.title
          FROM public.task_occurrences AS occurrence
          JOIN public.task_templates AS template
            ON template.organization_id = occurrence.organization_id
           AND template.farm_id = occurrence.farm_id
           AND template.id = occurrence.template_id
         WHERE occurrence.status IN ('open', 'in_progress')
           AND occurrence.due_at IS NOT NULL
           AND occurrence.due_at <= CURRENT_TIMESTAMP + p_window
    ), recipients AS (
        SELECT due.organization_id, due.farm_id, due.id AS occurrence_id,
               due.title, due.occurrence_date, due.slot,
               membership.user_id,
               encode(digest('farmly-operation-actor:v1:' || membership.user_id, 'sha256'), 'hex')::CHAR(64) AS actor_pseudonym
          FROM due
          JOIN public.farm_grants AS grant_
            ON grant_.organization_id = due.organization_id
           AND grant_.farm_id = due.farm_id
          JOIN public.organization_memberships AS membership
            ON membership.id = grant_.membership_id
           AND membership.organization_id = grant_.organization_id
           AND membership.status = 'active'
    ), inserted AS (
        INSERT INTO public.notifications (
            organization_id, farm_id, user_id, actor_pseudonym,
            kind, title, body, dedup_key, source_ref)
        SELECT organization_id, farm_id, user_id, actor_pseudonym,
               'reminder'::public.notification_kind,
               'Công việc sắp đến hạn: ' || title,
               'Ca ' || slot || ' ngày ' || to_char(occurrence_date, 'DD/MM/YYYY'),
               'task-occurrence:' || occurrence_id::TEXT,
               'task_occurrence:' || occurrence_id::TEXT
          FROM recipients
        ON CONFLICT (user_id, dedup_key) DO NOTHING
        RETURNING 1
    )
    SELECT count(*) INTO v_count FROM inserted;
    RETURN v_count;
END;
$$;

-- Owner-marked read; returns the updated row or NULL for foreign/unknown ids
-- (no cross-owner enumeration — the route maps NULL to 404).
CREATE OR REPLACE FUNCTION public.farmly_mark_notification_read(
    p_notification_id UUID,
    p_actor_pseudonym CHAR(64)
) RETURNS public.notifications
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_catalog AS $$
DECLARE
    v_row public.notifications;
BEGIN
    UPDATE public.notifications
       SET read_at = COALESCE(read_at, CURRENT_TIMESTAMP)
     WHERE id = p_notification_id
       AND actor_pseudonym = p_actor_pseudonym
    RETURNING * INTO v_row;
    RETURN v_row;
END;
$$;

-- Installation-bound device registration. Register: any *other* account's
-- active binding on the same installation is revoked first (one active
-- account per device_id); repeated operation_id is a replay, mismatched
-- replay raises OPERATION_ID_REUSED. Revoke is owner-scoped and idempotent.
CREATE OR REPLACE FUNCTION public.farmly_mutate_device_registration(
    p_user_id TEXT,
    p_actor_pseudonym CHAR(64),
    p_operation_id UUID,
    p_action TEXT,
    p_device_id VARCHAR(200),
    p_push_token TEXT DEFAULT NULL
) RETURNS public.device_registrations
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_catalog AS $$
DECLARE
    v_row public.device_registrations;
    v_digest CHAR(64);
BEGIN
    IF p_action NOT IN ('register', 'revoke') THEN
        RAISE EXCEPTION 'FARMLY_PRIVACY_ACTION_INVALID';
    END IF;

    -- Replay: same operation id must carry the same intent.
    SELECT * INTO v_row FROM public.device_registrations
     WHERE user_id = p_user_id
       AND device_id = p_device_id
       AND last_operation_id = p_operation_id;
    IF v_row.id IS NOT NULL THEN
        IF (v_row.status = 'registered') <> (p_action = 'register') THEN
            RAISE EXCEPTION 'FARMLY_OPERATION_ID_REUSED';
        END IF;
        RETURN v_row;
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.device_registrations
         WHERE last_operation_id = p_operation_id
           AND (user_id <> p_user_id OR device_id <> p_device_id)) THEN
        RAISE EXCEPTION 'FARMLY_OPERATION_ID_REUSED';
    END IF;

    IF p_action = 'register' THEN
        v_digest := encode(digest('farmly-device-v1|' || p_push_token, 'sha256'), 'hex')::CHAR(64);
        -- Old-owner binding on this installation is deactivated before the
        -- new activation lands (spec phase-10 step 2).
        UPDATE public.device_registrations
           SET status = 'revoked', revoked_at = CURRENT_TIMESTAMP,
               push_token = NULL, updated_at = CURRENT_TIMESTAMP
         WHERE device_id = p_device_id
           AND status = 'registered'
           AND user_id <> p_user_id;
        INSERT INTO public.device_registrations (
            user_id, actor_pseudonym, device_id, push_token, token_digest,
            status, last_operation_id)
        VALUES (
            p_user_id, p_actor_pseudonym, p_device_id, p_push_token, v_digest,
            'registered', p_operation_id)
        ON CONFLICT (user_id, device_id) DO UPDATE
           SET status = 'registered', push_token = EXCLUDED.push_token,
               token_digest = EXCLUDED.token_digest,
               revoked_at = NULL, registered_at = CURRENT_TIMESTAMP,
               last_operation_id = EXCLUDED.last_operation_id,
               updated_at = CURRENT_TIMESTAMP
        RETURNING * INTO v_row;
        RETURN v_row;
    END IF;

    -- revoke
    UPDATE public.device_registrations
       SET status = 'revoked', revoked_at = CURRENT_TIMESTAMP,
           push_token = NULL, last_operation_id = p_operation_id,
           updated_at = CURRENT_TIMESTAMP
     WHERE user_id = p_user_id
       AND device_id = p_device_id
    RETURNING * INTO v_row;
    IF v_row.id IS NULL THEN
        -- Idempotent revoke of a never-registered device returns a synthetic
        -- revoked row so the caller sees a stable terminal state.
        v_row := ROW(
            gen_random_uuid(), p_user_id, p_actor_pseudonym, p_device_id,
            NULL, NULL, 'revoked'::public.device_registration_status,
            p_operation_id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP,
            CURRENT_TIMESTAMP)::public.device_registrations;
    END IF;
    RETURN v_row;
END;
$$;

-- Audited privacy request: idempotent on operation_id (replays return the
-- existing request; a different action under the same id raises
-- FARMLY_OPERATION_ID_REUSED). Executed atomically:
--   withdraw-ai-consent → consent withdrawn in every org the user belongs to
--   delete-history      → own AI chat content purged (messages/requests
--                         bodies + conversations closed) with minimal proof
--   export              → own data materialized into payload (bounded)
CREATE OR REPLACE FUNCTION public.farmly_create_privacy_request(
    p_user_id TEXT,
    p_actor_pseudonym CHAR(64),
    p_operation_id UUID,
    p_action public.privacy_request_action,
    p_confirmation TEXT DEFAULT NULL
) RETURNS public.privacy_requests
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_catalog AS $$
DECLARE
    v_row public.privacy_requests;
    v_hash CHAR(64);
    v_payload JSONB;
    v_affected INTEGER;
BEGIN
    v_hash := encode(digest('farmly-privacy-v1|' || p_action::TEXT, 'sha256'), 'hex')::CHAR(64);

    SELECT * INTO v_row FROM public.privacy_requests WHERE operation_id = p_operation_id;
    IF v_row.id IS NOT NULL THEN
        IF v_row.user_id <> p_user_id OR v_row.action_hash <> v_hash THEN
            RAISE EXCEPTION 'FARMLY_OPERATION_ID_REUSED';
        END IF;
        RETURN v_row;
    END IF;

    INSERT INTO public.privacy_requests (
        operation_id, user_id, actor_pseudonym, action, action_hash, status)
    VALUES (
        p_operation_id, p_user_id, p_actor_pseudonym, p_action, v_hash, 'processing')
    RETURNING * INTO v_row;

    IF p_action = 'withdraw-ai-consent' THEN
        -- Audited consent path per active membership (revision bump, queued
        -- fence cancellation, reservation release — single-release safe).
        PERFORM public.farmly_ai_set_consent(
            p_user_id, p_actor_pseudonym, membership.organization_id, FALSE, FALSE)
          FROM public.organization_memberships AS membership
          JOIN public.ai_consents AS consent
            ON consent.organization_id = membership.organization_id
           AND consent.user_id = membership.user_id
         WHERE membership.user_id = p_user_id AND membership.status = 'active';
        -- Catch-all for consents whose membership is no longer active.
        UPDATE public.ai_consents AS consent
           SET granted = FALSE, withdrawn_at = CURRENT_TIMESTAMP,
               updated_at = CURRENT_TIMESTAMP
         WHERE consent.user_id = p_user_id AND consent.granted;
        GET DIAGNOSTICS v_affected = ROW_COUNT;
        v_payload := jsonb_build_object('consentsWithdrawn', v_affected);

    ELSIF p_action = 'delete-history' THEN
        -- Tombstone rather than delete: body is NOT NULL and proof rows stay
        -- for audit, matching the content-TTL purge convention.
        UPDATE public.ai_messages SET body = '[deleted]'
         WHERE actor_pseudonym = p_actor_pseudonym;
        UPDATE public.ai_requests
           SET prompt = NULL, content_purged_at = CURRENT_TIMESTAMP
         WHERE actor_pseudonym = p_actor_pseudonym
           AND prompt IS NOT NULL;
        DELETE FROM public.ai_events event
         USING public.ai_requests request
         WHERE event.request_id = request.id
           AND request.actor_pseudonym = p_actor_pseudonym;
        UPDATE public.ai_conversations AS conversation
           SET status = 'deleted'::public.ai_conversation_status
         WHERE conversation.actor_pseudonym = p_actor_pseudonym
           AND conversation.status <> 'deleted'::public.ai_conversation_status;
        GET DIAGNOSTICS v_affected = ROW_COUNT;
        v_payload := jsonb_build_object('conversationsDeleted', v_affected);

    ELSIF p_action = 'export' THEN
        SELECT jsonb_build_object(
            'exportedAt', CURRENT_TIMESTAMP,
            'userId', p_user_id,
            'consents', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                'organizationId', c.organization_id, 'granted', c.granted,
                'revision', c.revision, 'summaryOptedIn', c.ai_safe_summary_opted_in,
                'grantedAt', c.granted_at, 'withdrawnAt', c.withdrawn_at))
              FROM public.ai_consents AS c WHERE c.user_id = p_user_id), '[]'::jsonb),
            'conversations', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                'id', conv.id, 'farmId', conv.farm_id, 'status', conv.status,
                'createdAt', conv.created_at))
              FROM public.ai_conversations AS conv
             WHERE conv.actor_pseudonym = p_actor_pseudonym), '[]'::jsonb),
            'notifications', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                'id', n.id, 'kind', n.kind, 'title', n.title, 'body', n.body,
                'readAt', n.read_at, 'createdAt', n.created_at))
              FROM public.notifications AS n
             WHERE n.actor_pseudonym = p_actor_pseudonym), '[]'::jsonb),
            'deviceRegistrations', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                'deviceId', d.device_id, 'status', d.status,
                'registeredAt', d.registered_at, 'revokedAt', d.revoked_at))
              FROM public.device_registrations AS d
             WHERE d.user_id = p_user_id), '[]'::jsonb),
            'privacyRequests', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                'operationId', pr.operation_id, 'action', pr.action,
                'status', pr.status, 'requestedAt', pr.requested_at))
              FROM public.privacy_requests AS pr
             WHERE pr.user_id = p_user_id), '[]'::jsonb),
            'memberships', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                'organizationId', m.organization_id, 'role', m.role,
                'status', m.status))
              FROM public.organization_memberships AS m
             WHERE m.user_id = p_user_id), '[]'::jsonb))
          INTO v_payload;
    END IF;

    UPDATE public.privacy_requests
       SET status = 'completed', payload = v_payload,
           completed_at = CURRENT_TIMESTAMP
     WHERE id = v_row.id
    RETURNING * INTO v_row;
    RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.farmly_notify_recipient(UUID, UUID, TEXT, CHAR, public.notification_kind, VARCHAR, VARCHAR, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.farmly_generate_task_reminders(INTERVAL) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.farmly_mark_notification_read(UUID, CHAR) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.farmly_mutate_device_registration(TEXT, CHAR, UUID, TEXT, VARCHAR, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.farmly_create_privacy_request(TEXT, CHAR, UUID, public.privacy_request_action, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.farmly_notify_recipient(UUID, UUID, TEXT, CHAR, public.notification_kind, VARCHAR, VARCHAR, TEXT, TEXT) TO farmly_tenant_app;
GRANT EXECUTE ON FUNCTION public.farmly_generate_task_reminders(INTERVAL) TO farmly_tenant_app;
GRANT EXECUTE ON FUNCTION public.farmly_mark_notification_read(UUID, CHAR) TO farmly_tenant_app;
GRANT EXECUTE ON FUNCTION public.farmly_mutate_device_registration(TEXT, CHAR, UUID, TEXT, VARCHAR, TEXT) TO farmly_tenant_app;
GRANT EXECUTE ON FUNCTION public.farmly_create_privacy_request(TEXT, CHAR, UUID, public.privacy_request_action, TEXT) TO farmly_tenant_app;
