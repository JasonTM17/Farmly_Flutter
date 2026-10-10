CREATE TABLE public.organization_control_receipts (
    organization_id UUID NOT NULL,
    actor_id TEXT NOT NULL,
    operation_id UUID NOT NULL,
    action TEXT NOT NULL CHECK (action IN ('membership.patch', 'ownership.transfer')),
    request_hash CHAR(64) NOT NULL CHECK (request_hash ~ '^[a-f0-9]{64}$'),
    result JSONB NOT NULL CHECK (jsonb_typeof(result) = 'object'),
    created_at TIMESTAMPTZ(6) NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT organization_control_receipts_pkey PRIMARY KEY (organization_id, actor_id, operation_id),
    CONSTRAINT organization_control_receipts_organization_fkey
        FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE,
    CONSTRAINT organization_control_receipts_actor_fkey
        FOREIGN KEY (actor_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
);
ALTER TABLE public.organization_control_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_control_receipts FORCE ROW LEVEL SECURITY;
CREATE POLICY organization_control_receipts_migration_access ON public.organization_control_receipts
    FOR ALL TO farmly_migration USING (TRUE) WITH CHECK (TRUE);
REVOKE ALL ON TABLE public.organization_control_receipts FROM PUBLIC, farmly_tenant_app, farmly_auth_app;

CREATE FUNCTION public.list_organization_memberships(
    p_organization_id UUID,
    p_limit INTEGER,
    p_after_id UUID DEFAULT NULL
) RETURNS TABLE(
    membership_id UUID,
    user_id TEXT,
    organization_role public.organization_role,
    membership_status public.membership_status,
    membership_version INTEGER,
    farm_grants JSONB
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
BEGIN
    PERFORM public.farmly_require_organization_manager(p_organization_id);
    IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid membership page size';
    END IF;

    RETURN QUERY
    SELECT membership.id,
           membership.user_id,
           membership.role,
           membership.status,
           membership.version,
           COALESCE((
               SELECT jsonb_agg(jsonb_build_object(
                   'farmId', grant_row.farm_id::TEXT,
                   'role', grant_row.role::TEXT,
                   'version', grant_row.version
               ) ORDER BY grant_row.farm_id)
                 FROM public.farm_grants AS grant_row
                WHERE grant_row.organization_id = membership.organization_id
                  AND grant_row.membership_id = membership.id
           ), '[]'::JSONB)
      FROM public.organization_memberships AS membership
     WHERE membership.organization_id = p_organization_id
       AND (p_after_id IS NULL OR membership.id > p_after_id)
     ORDER BY membership.id
     LIMIT p_limit + 1;
END;
$$;

CREATE FUNCTION public.update_organization_membership(
    p_organization_id UUID,
    p_membership_id UUID,
    p_operation_id UUID,
    p_request_hash TEXT,
    p_role public.organization_role,
    p_farm_grants JSONB
) RETURNS TABLE(result JSONB, replayed BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
    actor_id TEXT := NULLIF(current_setting('app.actor_id', TRUE), '');
    actor_role public.organization_role;
    target_role public.organization_role;
    target_status public.membership_status;
    existing_hash CHAR(64);
    existing_action TEXT;
    existing_result JSONB;
    grant_item JSONB;
    grant_count INTEGER;
    current_grants JSONB;
    requested_grants JSONB;
    membership_changed BOOLEAN;
    grants_changed BOOLEAN;
    resulting_policy_version BIGINT;
    result_membership JSONB;
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
    IF actor_id IS NULL OR p_membership_id IS NULL OR p_operation_id IS NULL
       OR p_request_hash IS NULL OR p_request_hash !~ '^[a-f0-9]{64}$'
       OR p_role IS NULL OR p_role = 'owner'
       OR p_farm_grants IS NULL OR jsonb_typeof(p_farm_grants) <> 'array' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid membership request';
    END IF;

    SELECT receipt.request_hash, receipt.action, receipt.result
      INTO existing_hash, existing_action, existing_result
      FROM public.organization_control_receipts AS receipt
     WHERE receipt.organization_id = p_organization_id
       AND receipt.actor_id = actor_id
       AND receipt.operation_id = p_operation_id;
    IF FOUND THEN
        IF existing_action <> 'membership.patch' OR existing_hash <> p_request_hash THEN
            RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'organization operation id reused';
        END IF;
        RETURN QUERY SELECT jsonb_set(existing_result, '{replayed}', 'true'::JSONB, TRUE), TRUE;
        RETURN;
    END IF;

    SELECT membership.role, membership.status
      INTO target_role, target_status
      FROM public.organization_memberships AS membership
     WHERE membership.organization_id = p_organization_id
       AND membership.id = p_membership_id
     FOR UPDATE;
    IF NOT FOUND OR target_status = 'removed' THEN
        RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'FARMLY_MEMBERSHIP_NOT_AVAILABLE';
    END IF;
    IF target_role = 'owner' AND actor_role <> 'owner' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'organization owner membership protected';
    END IF;

    SELECT jsonb_array_length(p_farm_grants) INTO grant_count;
    IF grant_count > 100 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid membership grant count';
    END IF;
    IF (
        SELECT count(DISTINCT (item.value ->> 'farmId')::UUID)
          FROM jsonb_array_elements(p_farm_grants) AS item(value)
    ) <> grant_count THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'duplicate membership farm grant';
    END IF;
    IF p_role = 'admin' AND grant_count > 0 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'organization admin cannot have farm grants';
    END IF;

    FOR grant_item IN SELECT value FROM jsonb_array_elements(p_farm_grants) AS item(value)
    LOOP
        IF jsonb_typeof(grant_item) <> 'object'
           OR jsonb_object_length(grant_item) <> 2
           OR NOT (grant_item ? 'farmId') OR NOT (grant_item ? 'role') THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid membership farm grant';
        END IF;
        IF (grant_item ->> 'role') NOT IN ('manager', 'worker', 'viewer') THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid membership farm grant role';
        END IF;
        IF p_role = 'viewer' AND grant_item ->> 'role' <> 'viewer' THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'viewer membership grants must remain read only';
        END IF;
        IF NOT EXISTS (
            SELECT 1
              FROM public.farms AS farm
             WHERE farm.organization_id = p_organization_id
               AND farm.id = (grant_item ->> 'farmId')::UUID
        ) THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'membership farm grant outside organization';
        END IF;
    END LOOP;

    SELECT COALESCE(jsonb_agg(jsonb_build_object('farmId', grant_row.farm_id::TEXT, 'role', grant_row.role::TEXT)
                              ORDER BY grant_row.farm_id), '[]'::JSONB)
      INTO current_grants
      FROM public.farm_grants AS grant_row
     WHERE grant_row.organization_id = p_organization_id
       AND grant_row.membership_id = p_membership_id;
    SELECT COALESCE(jsonb_agg(jsonb_build_object('farmId', (item.value ->> 'farmId')::UUID::TEXT,
                                                'role', item.value ->> 'role')
                              ORDER BY (item.value ->> 'farmId')::UUID), '[]'::JSONB)
      INTO requested_grants
      FROM jsonb_array_elements(p_farm_grants) AS item(value);
    grants_changed := current_grants <> requested_grants;
    membership_changed := target_role <> p_role OR grants_changed;

    IF target_role = 'owner' AND p_role <> 'owner' AND membership_changed THEN
        IF (SELECT count(*) FROM public.organization_memberships AS owner_row
             WHERE owner_row.organization_id = p_organization_id
               AND owner_row.status = 'active'
               AND owner_row.role = 'owner') <= 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FARMLY_LAST_OWNER_CONFLICT';
        END IF;
    END IF;

    IF membership_changed THEN
        UPDATE public.organization_memberships AS membership
           SET role = p_role,
               version = membership.version + 1,
               updated_at = clock_timestamp()
         WHERE membership.organization_id = p_organization_id
           AND membership.id = p_membership_id;

        DELETE FROM public.farm_grants AS grant_row
         WHERE grant_row.organization_id = p_organization_id
           AND grant_row.membership_id = p_membership_id
           AND NOT EXISTS (
               SELECT 1 FROM jsonb_array_elements(p_farm_grants) AS item(value)
                WHERE (item.value ->> 'farmId')::UUID = grant_row.farm_id
           );

        INSERT INTO public.farm_grants (organization_id, membership_id, farm_id, role)
        SELECT p_organization_id,
               p_membership_id,
               (item.value ->> 'farmId')::UUID,
               (item.value ->> 'role')::public.farm_grant_role
          FROM jsonb_array_elements(p_farm_grants) AS item(value)
        ON CONFLICT (organization_id, membership_id, farm_id) DO UPDATE
          SET role = EXCLUDED.role,
              version = public.farm_grants.version + 1,
              updated_at = clock_timestamp()
        WHERE public.farm_grants.role IS DISTINCT FROM EXCLUDED.role;

        UPDATE public.organizations AS organization
           SET policy_version = organization.policy_version + 1,
               updated_at = clock_timestamp()
         WHERE organization.id = p_organization_id
        RETURNING organization.policy_version INTO resulting_policy_version;
    ELSE
        SELECT organization.policy_version INTO resulting_policy_version
          FROM public.organizations AS organization
         WHERE organization.id = p_organization_id;
    END IF;

    SELECT jsonb_build_object(
        'id', membership.id,
        'userId', membership.user_id,
        'role', membership.role,
        'status', membership.status,
        'version', membership.version,
        'farmGrants', COALESCE((
            SELECT jsonb_agg(jsonb_build_object('farmId', grant_row.farm_id::TEXT,
                                                'role', grant_row.role::TEXT,
                                                'version', grant_row.version)
                             ORDER BY grant_row.farm_id)
              FROM public.farm_grants AS grant_row
             WHERE grant_row.organization_id = membership.organization_id
               AND grant_row.membership_id = membership.id
        ), '[]'::JSONB)
    ) INTO result_membership
      FROM public.organization_memberships AS membership
     WHERE membership.organization_id = p_organization_id
       AND membership.id = p_membership_id;

    existing_result := jsonb_build_object(
        'membership', result_membership,
        'policyVersion', resulting_policy_version::TEXT,
        'changed', membership_changed,
        'replayed', FALSE
    );
    INSERT INTO public.organization_control_receipts(
        organization_id, actor_id, operation_id, action, request_hash, result
    ) VALUES (
        p_organization_id, actor_id, p_operation_id, 'membership.patch', p_request_hash, existing_result
    );
    RETURN QUERY SELECT existing_result, FALSE;
END;
$$;

CREATE FUNCTION public.remove_organization_membership(
    p_organization_id UUID,
    p_membership_id UUID
) RETURNS TABLE(result JSONB, changed BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
    actor_role public.organization_role;
    target_user_id TEXT;
    target_role public.organization_role;
    target_status public.membership_status;
    membership_version INTEGER;
    changed BOOLEAN := FALSE;
    resulting_policy_version BIGINT;
    result_membership JSONB;
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

    SELECT membership.user_id, membership.role, membership.status, membership.version
      INTO target_user_id, target_role, target_status, membership_version
      FROM public.organization_memberships AS membership
     WHERE membership.organization_id = p_organization_id
       AND membership.id = p_membership_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'FARMLY_MEMBERSHIP_NOT_AVAILABLE';
    END IF;
    IF target_role = 'owner' AND actor_role <> 'owner' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'organization owner membership protected';
    END IF;

    IF target_status <> 'removed' THEN
        IF target_role = 'owner'
           AND (SELECT count(*) FROM public.organization_memberships AS owner_row
                 WHERE owner_row.organization_id = p_organization_id
                   AND owner_row.status = 'active'
                   AND owner_row.role = 'owner') <= 1 THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FARMLY_LAST_OWNER_CONFLICT';
        END IF;
        UPDATE public.organization_memberships AS membership
           SET status = 'removed',
               version = membership.version + 1,
               updated_at = clock_timestamp()
         WHERE membership.organization_id = p_organization_id
           AND membership.id = p_membership_id
        RETURNING membership.version INTO membership_version;
        DELETE FROM public.farm_grants AS grant_row
         WHERE grant_row.organization_id = p_organization_id
           AND grant_row.membership_id = p_membership_id;
        UPDATE public.organizations AS organization
           SET policy_version = organization.policy_version + 1,
               updated_at = clock_timestamp()
         WHERE organization.id = p_organization_id
        RETURNING organization.policy_version INTO resulting_policy_version;
        changed := TRUE;
    ELSE
        SELECT organization.policy_version INTO resulting_policy_version
          FROM public.organizations AS organization
         WHERE organization.id = p_organization_id;
    END IF;

    result_membership := jsonb_build_object(
        'id', p_membership_id,
        'userId', target_user_id,
        'role', target_role,
        'status', 'removed',
        'version', membership_version,
        'farmGrants', '[]'::JSONB
    );
    RETURN QUERY SELECT jsonb_build_object(
        'membership', result_membership,
        'policyVersion', resulting_policy_version::TEXT,
        'changed', changed,
        'replayed', FALSE
    ), changed;
END;
$$;

CREATE FUNCTION public.transfer_organization_ownership(
    p_organization_id UUID,
    p_operation_id UUID,
    p_request_hash TEXT,
    p_target_membership_id UUID,
    p_remove_former_owner BOOLEAN
) RETURNS TABLE(result JSONB, replayed BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
    actor_id TEXT := NULLIF(current_setting('app.actor_id', TRUE), '');
    actor_role public.organization_role;
    former_membership_id UUID;
    target_role public.organization_role;
    target_status public.membership_status;
    existing_hash CHAR(64);
    existing_action TEXT;
    existing_result JSONB;
    resulting_policy_version BIGINT;
    former_role public.organization_role;
    former_status public.membership_status;
    transfer_result JSONB;
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
    IF actor_id IS NULL OR p_operation_id IS NULL OR p_request_hash IS NULL
       OR p_request_hash !~ '^[a-f0-9]{64}$' OR p_target_membership_id IS NULL
       OR p_remove_former_owner IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid ownership transfer request';
    END IF;

    SELECT receipt.request_hash, receipt.action, receipt.result
      INTO existing_hash, existing_action, existing_result
      FROM public.organization_control_receipts AS receipt
     WHERE receipt.organization_id = p_organization_id
       AND receipt.actor_id = actor_id
       AND receipt.operation_id = p_operation_id;
    IF FOUND THEN
        IF existing_action <> 'ownership.transfer' OR existing_hash <> p_request_hash THEN
            RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'organization operation id reused';
        END IF;
        RETURN QUERY SELECT jsonb_set(existing_result, '{replayed}', 'true'::JSONB, TRUE), TRUE;
        RETURN;
    END IF;
    IF actor_role <> 'owner' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ownership transfer requires current owner';
    END IF;

    SELECT membership.id
      INTO former_membership_id
      FROM public.organization_memberships AS membership
     WHERE membership.organization_id = p_organization_id
       AND membership.user_id = actor_id
       AND membership.status = 'active'
       AND membership.role = 'owner'
     FOR UPDATE;
    SELECT membership.role, membership.status
      INTO target_role, target_status
      FROM public.organization_memberships AS membership
     WHERE membership.organization_id = p_organization_id
       AND membership.id = p_target_membership_id
     FOR UPDATE;
    IF former_membership_id IS NULL OR NOT FOUND OR target_status <> 'active'
       OR p_target_membership_id = former_membership_id THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid ownership transfer target';
    END IF;

    UPDATE public.organization_memberships AS target
       SET role = 'owner',
           version = target.version + CASE WHEN target.role <> 'owner' THEN 1 ELSE 0 END,
           updated_at = clock_timestamp()
     WHERE target.organization_id = p_organization_id
       AND target.id = p_target_membership_id;
    DELETE FROM public.farm_grants AS grant_row
     WHERE grant_row.organization_id = p_organization_id
       AND grant_row.membership_id = p_target_membership_id;

    IF p_remove_former_owner THEN
        UPDATE public.organization_memberships AS former
           SET status = 'removed', version = former.version + 1, updated_at = clock_timestamp()
         WHERE former.organization_id = p_organization_id
           AND former.id = former_membership_id;
        former_role := 'owner';
        former_status := 'removed';
    ELSE
        UPDATE public.organization_memberships AS former
           SET role = 'admin',
               version = former.version + CASE WHEN former.role <> 'admin' THEN 1 ELSE 0 END,
               updated_at = clock_timestamp()
         WHERE former.organization_id = p_organization_id
           AND former.id = former_membership_id;
        former_role := 'admin';
        former_status := 'active';
    END IF;
    DELETE FROM public.farm_grants AS grant_row
     WHERE grant_row.organization_id = p_organization_id
       AND grant_row.membership_id = former_membership_id;

    UPDATE public.organizations AS organization
       SET policy_version = organization.policy_version + 1,
           updated_at = clock_timestamp()
     WHERE organization.id = p_organization_id
    RETURNING organization.policy_version INTO resulting_policy_version;

    transfer_result := jsonb_build_object(
        'targetMembershipId', p_target_membership_id,
        'formerOwnerMembershipId', former_membership_id,
        'formerOwnerRole', former_role,
        'formerOwnerStatus', former_status,
        'policyVersion', resulting_policy_version::TEXT,
        'replayed', FALSE
    );
    INSERT INTO public.organization_control_receipts(
        organization_id, actor_id, operation_id, action, request_hash, result
    ) VALUES (
        p_organization_id, actor_id, p_operation_id, 'ownership.transfer', p_request_hash, transfer_result
    );
    RETURN QUERY SELECT transfer_result, FALSE;
END;
$$;

REVOKE ALL ON FUNCTION public.list_organization_memberships(UUID, INTEGER, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_organization_membership(UUID, UUID, UUID, TEXT, public.organization_role, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.remove_organization_membership(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.transfer_organization_ownership(UUID, UUID, TEXT, UUID, BOOLEAN) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.list_organization_memberships(UUID, INTEGER, UUID) TO farmly_tenant_app;
GRANT EXECUTE ON FUNCTION public.update_organization_membership(UUID, UUID, UUID, TEXT, public.organization_role, JSONB) TO farmly_tenant_app;
GRANT EXECUTE ON FUNCTION public.remove_organization_membership(UUID, UUID) TO farmly_tenant_app;
GRANT EXECUTE ON FUNCTION public.transfer_organization_ownership(UUID, UUID, TEXT, UUID, BOOLEAN) TO farmly_tenant_app;
