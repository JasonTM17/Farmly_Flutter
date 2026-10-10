-- Preserve same-operation replay after a transfer removes or demotes the former owner.
CREATE OR REPLACE FUNCTION public.transfer_organization_ownership(
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
    verified BOOLEAN;
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

    IF actor_id IS NULL OR p_operation_id IS NULL OR p_request_hash IS NULL
       OR p_request_hash !~ '^[a-f0-9]{64}$' OR p_target_membership_id IS NULL
       OR p_remove_former_owner IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid ownership transfer request';
    END IF;

    SELECT user_row."emailVerified" INTO verified
      FROM auth."user" AS user_row
     WHERE user_row.id = actor_id;
    IF NOT COALESCE(verified, FALSE) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'verified principal required';
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

    actor_role := public.farmly_require_organization_manager(p_organization_id);
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

REVOKE ALL ON FUNCTION public.transfer_organization_ownership(UUID, UUID, TEXT, UUID, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.transfer_organization_ownership(UUID, UUID, TEXT, UUID, BOOLEAN) TO farmly_tenant_app;
