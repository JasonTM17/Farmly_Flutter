DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'farmly_tenant_app')
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'farmly_auth_app')
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'farmly_migration') THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'Farmly database roles must be provisioned before tenant RLS';
    END IF;
END;
$$;

REVOKE ALL PRIVILEGES ON TABLE
    public.organizations,
    public.organization_memberships,
    public.farms,
    public.farm_grants,
    public.organization_invitations,
    public.invitation_farm_grants,
    public.organization_creation_receipts
FROM PUBLIC, farmly_auth_app, farmly_tenant_app;

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organizations FORCE ROW LEVEL SECURITY;
ALTER TABLE public.organization_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_memberships FORCE ROW LEVEL SECURITY;
ALTER TABLE public.farms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.farms FORCE ROW LEVEL SECURITY;
ALTER TABLE public.farm_grants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.farm_grants FORCE ROW LEVEL SECURITY;
ALTER TABLE public.organization_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_invitations FORCE ROW LEVEL SECURITY;
ALTER TABLE public.invitation_farm_grants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invitation_farm_grants FORCE ROW LEVEL SECURITY;
ALTER TABLE public.organization_creation_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_creation_receipts FORCE ROW LEVEL SECURITY;

CREATE POLICY organizations_migration_access ON public.organizations
    TO farmly_migration USING (TRUE) WITH CHECK (TRUE);
CREATE POLICY memberships_migration_access ON public.organization_memberships
    TO farmly_migration USING (TRUE) WITH CHECK (TRUE);
CREATE POLICY farms_migration_access ON public.farms
    TO farmly_migration USING (TRUE) WITH CHECK (TRUE);
CREATE POLICY farm_grants_migration_access ON public.farm_grants
    TO farmly_migration USING (TRUE) WITH CHECK (TRUE);
CREATE POLICY invitations_migration_access ON public.organization_invitations
    TO farmly_migration USING (TRUE) WITH CHECK (TRUE);
CREATE POLICY invitation_farm_grants_migration_access ON public.invitation_farm_grants
    TO farmly_migration USING (TRUE) WITH CHECK (TRUE);
CREATE POLICY creation_receipts_migration_access ON public.organization_creation_receipts
    TO farmly_migration USING (TRUE) WITH CHECK (TRUE);

CREATE FUNCTION public.farmly_actor_has_organization_access(p_organization_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    actor_id TEXT := NULLIF(current_setting('app.actor_id', TRUE), '');
BEGIN
    IF actor_id IS NULL OR p_organization_id IS NULL THEN RETURN FALSE; END IF;

    RETURN EXISTS (
        SELECT 1
          FROM public.organization_memberships AS membership
         WHERE membership.organization_id = p_organization_id
           AND membership.user_id = actor_id
           AND membership.status = 'active'
    );
END;
$$;

CREATE FUNCTION public.farmly_actor_can_manage_organization(p_organization_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    actor_id TEXT := NULLIF(current_setting('app.actor_id', TRUE), '');
BEGIN
    IF actor_id IS NULL OR p_organization_id IS NULL THEN RETURN FALSE; END IF;

    RETURN EXISTS (
        SELECT 1
          FROM public.organization_memberships AS membership
          JOIN public.organizations AS organization
            ON organization.id = membership.organization_id
         WHERE membership.organization_id = p_organization_id
           AND membership.user_id = actor_id
           AND membership.status = 'active'
           AND membership.role IN ('owner', 'admin')
           AND organization.status = 'active'
    );
END;
$$;

CREATE FUNCTION public.farmly_actor_can_read_farm(
    p_organization_id UUID,
    p_farm_id UUID
) RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    actor_id TEXT := NULLIF(current_setting('app.actor_id', TRUE), '');
BEGIN
    IF actor_id IS NULL OR p_organization_id IS NULL OR p_farm_id IS NULL THEN RETURN FALSE; END IF;

    RETURN EXISTS (
        SELECT 1
          FROM public.organizations AS organization
          JOIN public.organization_memberships AS membership
            ON membership.organization_id = organization.id
          JOIN public.farms AS farm
            ON farm.organization_id = organization.id
         WHERE organization.id = p_organization_id
           AND organization.status = 'active'
           AND membership.user_id = actor_id
           AND membership.status = 'active'
           AND farm.id = p_farm_id
           AND (
               membership.role IN ('owner', 'admin')
               OR EXISTS (
                   SELECT 1
                     FROM public.farm_grants AS grant_row
                    WHERE grant_row.organization_id = organization.id
                      AND grant_row.membership_id = membership.id
                      AND grant_row.farm_id = farm.id
               )
           )
    );
END;
$$;

CREATE FUNCTION public.farmly_actor_can_read_farm_grant(
    p_organization_id UUID,
    p_membership_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    actor_id TEXT := NULLIF(current_setting('app.actor_id', TRUE), '');
BEGIN
    IF actor_id IS NULL OR p_organization_id IS NULL OR p_membership_id IS NULL THEN RETURN FALSE; END IF;

    RETURN EXISTS (
        SELECT 1
          FROM public.organization_memberships AS membership
          JOIN public.organizations AS organization
            ON organization.id = membership.organization_id
         WHERE membership.organization_id = p_organization_id
           AND membership.user_id = actor_id
           AND membership.status = 'active'
           AND organization.status = 'active'
           AND (
               membership.role IN ('owner', 'admin')
               OR membership.id = p_membership_id
           )
    );
END;
$$;

REVOKE ALL ON FUNCTION public.farmly_actor_has_organization_access(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.farmly_actor_can_manage_organization(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.farmly_actor_can_read_farm(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.farmly_actor_can_read_farm_grant(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.farmly_actor_has_organization_access(UUID) TO farmly_tenant_app;
GRANT EXECUTE ON FUNCTION public.farmly_actor_can_manage_organization(UUID) TO farmly_tenant_app;
GRANT EXECUTE ON FUNCTION public.farmly_actor_can_read_farm(UUID, UUID) TO farmly_tenant_app;
GRANT EXECUTE ON FUNCTION public.farmly_actor_can_read_farm_grant(UUID, UUID) TO farmly_tenant_app;

CREATE POLICY organizations_tenant_read ON public.organizations
    FOR SELECT TO farmly_tenant_app
    USING (public.farmly_actor_has_organization_access(id));
CREATE POLICY memberships_tenant_read ON public.organization_memberships
    FOR SELECT TO farmly_tenant_app
    USING (
        user_id = NULLIF(current_setting('app.actor_id', TRUE), '')
        OR public.farmly_actor_can_manage_organization(organization_id)
    );
CREATE POLICY farms_tenant_read ON public.farms
    FOR SELECT TO farmly_tenant_app
    USING (public.farmly_actor_can_read_farm(organization_id, id));
CREATE POLICY farm_grants_tenant_read ON public.farm_grants
    FOR SELECT TO farmly_tenant_app
    USING (public.farmly_actor_can_read_farm_grant(organization_id, membership_id));

GRANT SELECT ON TABLE
    public.organizations,
    public.organization_memberships,
    public.farms,
    public.farm_grants
TO farmly_tenant_app;
