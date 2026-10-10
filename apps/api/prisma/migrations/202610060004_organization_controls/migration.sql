ALTER TABLE public.organizations
    ADD COLUMN continuity_epoch BIGINT NOT NULL DEFAULT 1 CHECK (continuity_epoch >= 1);

ALTER TABLE public.organization_invitations
    ADD COLUMN revoked_by_user_id TEXT,
    ADD COLUMN revoke_operation_id UUID,
    ADD CONSTRAINT organization_invitations_revocation_pair
        CHECK ((revoked_at IS NULL) = (revoked_by_user_id IS NULL)
               AND (revoked_by_user_id IS NULL) = (revoke_operation_id IS NULL)),
    ADD CONSTRAINT organization_invitations_accept_revoke_exclusive
        CHECK (accepted_at IS NULL OR revoked_at IS NULL),
    ADD CONSTRAINT organization_invitations_revoker_fkey
        FOREIGN KEY (revoked_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT;

CREATE UNIQUE INDEX organization_invitations_revoke_operation_key
    ON public.organization_invitations(organization_id, revoked_by_user_id, revoke_operation_id)
    WHERE revoked_by_user_id IS NOT NULL AND revoke_operation_id IS NOT NULL;

CREATE FUNCTION public.farmly_require_organization_manager(p_organization_id UUID)
RETURNS public.organization_role
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
    actor_id TEXT := NULLIF(current_setting('app.actor_id', TRUE), '');
    actor_role public.organization_role;
    verified BOOLEAN;
BEGIN
    IF actor_id IS NULL OR p_organization_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'organization control unavailable';
    END IF;

    SELECT membership.role
      INTO actor_role
      FROM public.organization_memberships AS membership
      JOIN public.organizations AS organization
        ON organization.id = membership.organization_id
     WHERE membership.organization_id = p_organization_id
       AND membership.user_id = actor_id
       AND membership.status = 'active'
       AND organization.status = 'active';

    IF actor_role IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'organization control unavailable';
    END IF;

    SELECT user_row."emailVerified"
      INTO verified
      FROM auth."user" AS user_row
     WHERE user_row.id = actor_id;
    IF NOT COALESCE(verified, FALSE) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'verified principal required';
    END IF;

    IF actor_role NOT IN ('owner', 'admin') THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'organization control forbidden';
    END IF;

    RETURN actor_role;
END;
$$;

CREATE FUNCTION public.create_organization_invitation(
    p_organization_id UUID,
    p_operation_id UUID,
    p_email_hash TEXT,
    p_role public.organization_role,
    p_token_hash TEXT,
    p_farm_grants JSONB
) RETURNS TABLE(invitation_id UUID, created_at TIMESTAMPTZ, expires_at TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
    actor_id TEXT := NULLIF(current_setting('app.actor_id', TRUE), '');
    actor_role public.organization_role;
    farm_grant JSONB;
    grant_farm_id UUID;
    grant_role public.farm_grant_role;
    grant_count INTEGER;
    new_invitation_id UUID := gen_random_uuid();
    invitation_created_at TIMESTAMPTZ := clock_timestamp();
BEGIN
    PERFORM organization.id
      FROM public.organizations AS organization
     WHERE organization.id = p_organization_id
       AND organization.status = 'active'
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'organization control unavailable';
    END IF;

    actor_role := public.farmly_require_organization_manager(p_organization_id);
    IF p_operation_id IS NULL
       OR p_email_hash IS NULL OR p_email_hash !~ '^[a-f0-9]{64}$'
       OR p_token_hash IS NULL OR p_token_hash !~ '^[a-f0-9]{64}$'
       OR p_role IS NULL
       OR p_role = 'owner'
       OR p_farm_grants IS NULL
       OR jsonb_typeof(p_farm_grants) <> 'array' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid invitation request';
    END IF;

    SELECT jsonb_array_length(p_farm_grants) INTO grant_count;
    IF grant_count > 100 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid invitation grant count';
    END IF;
    IF (
        SELECT count(DISTINCT (item.value ->> 'farmId')::UUID)
          FROM jsonb_array_elements(p_farm_grants) AS item(value)
    ) <> grant_count THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'duplicate invitation farm grant';
    END IF;
    IF p_role IN ('admin') AND grant_count > 0 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'organization role does not accept farm grants';
    END IF;

    FOR farm_grant IN SELECT value FROM jsonb_array_elements(p_farm_grants) AS item(value)
    LOOP
        IF jsonb_typeof(farm_grant) <> 'object'
           OR NOT (farm_grant ? 'farmId')
           OR NOT (farm_grant ? 'role') THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid invitation farm grant';
        END IF;

        grant_farm_id := (farm_grant ->> 'farmId')::UUID;
        grant_role := (farm_grant ->> 'role')::public.farm_grant_role;
        IF grant_farm_id IS NULL OR grant_role IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid invitation farm grant';
        END IF;
        IF p_role = 'viewer' AND grant_role <> 'viewer' THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'viewer invitation grants must remain read only';
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM public.farms AS farm
             WHERE farm.organization_id = p_organization_id
               AND farm.id = grant_farm_id
        ) THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invitation farm grant is outside organization';
        END IF;
    END LOOP;

    INSERT INTO public.organization_invitations (
        id, organization_id, operation_id, email_hash, token_hash, role,
        created_by_user_id, created_at, expires_at
    ) VALUES (
        new_invitation_id, p_organization_id, p_operation_id, p_email_hash,
        p_token_hash, p_role, actor_id, invitation_created_at,
        invitation_created_at + INTERVAL '72 hours'
    ) RETURNING organization_invitations.created_at, organization_invitations.expires_at
      INTO invitation_created_at, expires_at;

    FOR farm_grant IN SELECT value FROM jsonb_array_elements(p_farm_grants) AS item(value)
    LOOP
        grant_farm_id := (farm_grant ->> 'farmId')::UUID;
        grant_role := (farm_grant ->> 'role')::public.farm_grant_role;
        INSERT INTO public.invitation_farm_grants(organization_id, invitation_id, farm_id, role)
        VALUES (p_organization_id, new_invitation_id, grant_farm_id, grant_role);
    END LOOP;

    RETURN QUERY SELECT new_invitation_id, invitation_created_at, expires_at;
END;
$$;

CREATE FUNCTION public.list_organization_invitations(
    p_organization_id UUID,
    p_limit INTEGER,
    p_after_id UUID DEFAULT NULL
) RETURNS TABLE(
    invitation_id UUID,
    organization_role public.organization_role,
    invitation_status TEXT,
    created_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    accepted_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
BEGIN
    PERFORM public.farmly_require_organization_manager(p_organization_id);
    IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid invitation page size';
    END IF;

    RETURN QUERY
    SELECT invitation.id,
           invitation.role,
           CASE
               WHEN invitation.revoked_at IS NOT NULL THEN 'revoked'
               WHEN invitation.accepted_at IS NOT NULL THEN 'accepted'
               WHEN invitation.expires_at <= clock_timestamp() THEN 'expired'
               ELSE 'pending'
           END,
           invitation.created_at,
           invitation.expires_at,
           invitation.accepted_at,
           invitation.revoked_at
      FROM public.organization_invitations AS invitation
     WHERE invitation.organization_id = p_organization_id
       AND (p_after_id IS NULL OR invitation.id > p_after_id)
     ORDER BY invitation.id
     LIMIT p_limit + 1;
END;
$$;

CREATE FUNCTION public.accept_organization_invitation(
    p_organization_id UUID,
    p_invitation_id UUID,
    p_email_hash TEXT,
    p_token_hash TEXT,
    p_operation_id UUID
) RETURNS TABLE(
    organization_id UUID,
    membership_id UUID,
    organization_role public.organization_role,
    membership_version INTEGER,
    policy_version BIGINT,
    replayed BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
    actor_id TEXT := NULLIF(current_setting('app.actor_id', TRUE), '');
    actor_verified BOOLEAN;
    invitation public.organization_invitations%ROWTYPE;
    existing_membership public.organization_memberships%ROWTYPE;
    new_membership_id UUID := gen_random_uuid();
    resulting_policy_version BIGINT;
BEGIN
    IF actor_id IS NULL OR p_organization_id IS NULL OR p_invitation_id IS NULL
       OR p_operation_id IS NULL OR p_email_hash IS NULL OR p_email_hash !~ '^[a-f0-9]{64}$'
       OR p_token_hash IS NULL OR p_token_hash !~ '^[a-f0-9]{64}$' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid invitation acceptance request';
    END IF;

    SELECT user_row."emailVerified"
      INTO actor_verified
      FROM auth."user" AS user_row
     WHERE user_row.id = actor_id;
    IF NOT COALESCE(actor_verified, FALSE) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'verified principal required';
    END IF;

    PERFORM organization.id
      FROM public.organizations AS organization
     WHERE organization.id = p_organization_id
       AND organization.status = 'active'
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FARMLY_INVITATION_UNAVAILABLE';
    END IF;

    SELECT *
      INTO invitation
      FROM public.organization_invitations AS invitation_row
     WHERE invitation_row.organization_id = p_organization_id
       AND invitation_row.id = p_invitation_id
     FOR UPDATE;
    IF NOT FOUND OR invitation.token_hash <> p_token_hash THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FARMLY_INVITATION_UNAVAILABLE';
    END IF;
    IF invitation.email_hash <> p_email_hash THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FARMLY_INVITATION_EMAIL_MISMATCH';
    END IF;

    IF invitation.accepted_at IS NOT NULL THEN
        IF invitation.accepted_by_user_id = actor_id
           AND invitation.accept_operation_id = p_operation_id THEN
            SELECT *
              INTO existing_membership
              FROM public.organization_memberships AS membership
             WHERE membership.organization_id = p_organization_id
               AND membership.user_id = actor_id
               AND membership.status = 'active';
            IF FOUND THEN
                SELECT organization.policy_version
                  INTO resulting_policy_version
                  FROM public.organizations AS organization
                 WHERE organization.id = p_organization_id;
                RETURN QUERY SELECT p_organization_id, existing_membership.id,
                    existing_membership.role, existing_membership.version,
                    resulting_policy_version, TRUE;
                RETURN;
            END IF;
        END IF;
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FARMLY_INVITATION_ALREADY_ACCEPTED';
    END IF;
    IF invitation.revoked_at IS NOT NULL THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FARMLY_INVITATION_REVOKED';
    END IF;
    IF invitation.expires_at <= clock_timestamp() THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FARMLY_INVITATION_EXPIRED';
    END IF;

    SELECT *
      INTO existing_membership
      FROM public.organization_memberships AS membership
     WHERE membership.organization_id = p_organization_id
       AND membership.user_id = actor_id
     FOR UPDATE;
    IF FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FARMLY_MEMBERSHIP_ALREADY_EXISTS';
    END IF;

    INSERT INTO public.organization_memberships(id, organization_id, user_id, role, status)
    VALUES (new_membership_id, p_organization_id, actor_id, invitation.role, 'active');

    INSERT INTO public.farm_grants(organization_id, membership_id, farm_id, role)
    SELECT p_organization_id, new_membership_id, grant_row.farm_id, grant_row.role
      FROM public.invitation_farm_grants AS grant_row
     WHERE grant_row.organization_id = p_organization_id
       AND grant_row.invitation_id = p_invitation_id;

    UPDATE public.organization_invitations
       SET accepted_at = clock_timestamp(),
           accepted_by_user_id = actor_id,
           accept_operation_id = p_operation_id
     WHERE organization_invitations.organization_id = p_organization_id
       AND organization_invitations.id = p_invitation_id;

    UPDATE public.organizations
       SET policy_version = policy_version + 1,
           updated_at = clock_timestamp()
     WHERE organizations.id = p_organization_id
    RETURNING organizations.policy_version INTO resulting_policy_version;

    RETURN QUERY SELECT p_organization_id, new_membership_id,
        invitation.role, 1, resulting_policy_version, FALSE;
END;
$$;

CREATE FUNCTION public.revoke_organization_invitation(
    p_organization_id UUID,
    p_invitation_id UUID,
    p_operation_id UUID
) RETURNS TABLE(
    invitation_id UUID,
    revoked_at TIMESTAMPTZ,
    policy_version BIGINT,
    replayed BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
    actor_id TEXT := NULLIF(current_setting('app.actor_id', TRUE), '');
    invitation public.organization_invitations%ROWTYPE;
    resulting_policy_version BIGINT;
    revocation_time TIMESTAMPTZ;
BEGIN
    IF actor_id IS NULL OR p_organization_id IS NULL OR p_invitation_id IS NULL OR p_operation_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid invitation revocation request';
    END IF;

    PERFORM organization.id
      FROM public.organizations AS organization
     WHERE organization.id = p_organization_id
       AND organization.status = 'active'
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'organization control unavailable';
    END IF;

    PERFORM public.farmly_require_organization_manager(p_organization_id);

    SELECT *
      INTO invitation
      FROM public.organization_invitations AS invitation_row
     WHERE invitation_row.organization_id = p_organization_id
       AND invitation_row.id = p_invitation_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FARMLY_INVITATION_UNAVAILABLE';
    END IF;
    IF invitation.accepted_at IS NOT NULL THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FARMLY_INVITATION_ALREADY_ACCEPTED';
    END IF;
    IF invitation.revoked_at IS NOT NULL THEN
        IF invitation.revoked_by_user_id = actor_id
           AND invitation.revoke_operation_id = p_operation_id THEN
            SELECT organization.policy_version
              INTO resulting_policy_version
              FROM public.organizations AS organization
             WHERE organization.id = p_organization_id;
            RETURN QUERY SELECT p_invitation_id, invitation.revoked_at, resulting_policy_version, TRUE;
            RETURN;
        END IF;
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FARMLY_INVITATION_REVOKED';
    END IF;

    revocation_time := clock_timestamp();
    UPDATE public.organization_invitations
       SET revoked_at = revocation_time,
           revoked_by_user_id = actor_id,
           revoke_operation_id = p_operation_id
     WHERE organization_invitations.organization_id = p_organization_id
       AND organization_invitations.id = p_invitation_id;

    UPDATE public.organizations
       SET policy_version = policy_version + 1,
           updated_at = clock_timestamp()
     WHERE organizations.id = p_organization_id
    RETURNING organizations.policy_version INTO resulting_policy_version;

    RETURN QUERY SELECT p_invitation_id, revocation_time, resulting_policy_version, FALSE;
END;
$$;

REVOKE ALL ON FUNCTION public.farmly_require_organization_manager(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_organization_invitation(UUID, UUID, TEXT, public.organization_role, TEXT, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_organization_invitations(UUID, INTEGER, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.accept_organization_invitation(UUID, UUID, TEXT, TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.revoke_organization_invitation(UUID, UUID, UUID) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_organization_invitation(UUID, UUID, TEXT, public.organization_role, TEXT, JSONB) TO farmly_tenant_app;
GRANT EXECUTE ON FUNCTION public.list_organization_invitations(UUID, INTEGER, UUID) TO farmly_tenant_app;
GRANT EXECUTE ON FUNCTION public.accept_organization_invitation(UUID, UUID, TEXT, TEXT, UUID) TO farmly_tenant_app;
GRANT EXECUTE ON FUNCTION public.revoke_organization_invitation(UUID, UUID, UUID) TO farmly_tenant_app;
