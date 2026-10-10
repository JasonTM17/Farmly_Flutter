-- Anchor the fixed invitation TTL after the organization lock and validation.

CREATE OR REPLACE FUNCTION public.create_organization_invitation(
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
    invitation_created_at TIMESTAMPTZ;
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

    invitation_created_at := clock_timestamp();

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
