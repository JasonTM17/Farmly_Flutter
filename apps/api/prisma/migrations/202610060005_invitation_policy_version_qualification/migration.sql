CREATE OR REPLACE FUNCTION public.accept_organization_invitation(
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
       SET policy_version = organizations.policy_version + 1,
           updated_at = clock_timestamp()
     WHERE organizations.id = p_organization_id
    RETURNING organizations.policy_version INTO resulting_policy_version;

    RETURN QUERY SELECT p_organization_id, new_membership_id,
        invitation.role, 1, resulting_policy_version, FALSE;
END;
$$;

CREATE OR REPLACE FUNCTION public.revoke_organization_invitation(
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
       SET policy_version = organizations.policy_version + 1,
           updated_at = clock_timestamp()
     WHERE organizations.id = p_organization_id
    RETURNING organizations.policy_version INTO resulting_policy_version;

    RETURN QUERY SELECT p_invitation_id, revocation_time, resulting_policy_version, FALSE;
END;
$$;
