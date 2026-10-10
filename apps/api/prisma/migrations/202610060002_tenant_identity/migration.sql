CREATE TYPE public.organization_status AS ENUM ('active', 'archived');
CREATE TYPE public.organization_role AS ENUM ('owner', 'admin', 'member', 'viewer');
CREATE TYPE public.membership_status AS ENUM ('active', 'suspended', 'removed');
CREATE TYPE public.farm_status AS ENUM ('active', 'archived');
CREATE TYPE public.farm_grant_role AS ENUM ('manager', 'worker', 'viewer');

CREATE TABLE public.organizations (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    name VARCHAR(160) NOT NULL,
    status public.organization_status NOT NULL DEFAULT 'active',
    policy_version BIGINT NOT NULL DEFAULT 1 CHECK (policy_version >= 1),
    created_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT organizations_pkey PRIMARY KEY (id),
    CONSTRAINT organizations_name_nonempty CHECK (length(btrim(name)) BETWEEN 1 AND 160)
);

CREATE TABLE public.organization_memberships (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL,
    user_id TEXT NOT NULL,
    role public.organization_role NOT NULL DEFAULT 'member',
    status public.membership_status NOT NULL DEFAULT 'active',
    version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
    created_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT organization_memberships_pkey PRIMARY KEY (id),
    CONSTRAINT organization_memberships_org_user_key UNIQUE (organization_id, user_id),
    CONSTRAINT organization_memberships_org_id_key UNIQUE (organization_id, id),
    CONSTRAINT organization_memberships_organization_fkey FOREIGN KEY (organization_id)
        REFERENCES public.organizations(id) ON DELETE CASCADE,
    CONSTRAINT organization_memberships_user_fkey FOREIGN KEY (user_id)
        REFERENCES auth."user"(id) ON DELETE RESTRICT
);
CREATE INDEX organization_memberships_user_status_idx ON public.organization_memberships(user_id, status);

CREATE TABLE public.farms (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL,
    name VARCHAR(160) NOT NULL,
    area_m2 NUMERIC(14, 2),
    timezone VARCHAR(64) NOT NULL,
    status public.farm_status NOT NULL DEFAULT 'active',
    version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
    created_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT farms_pkey PRIMARY KEY (id),
    CONSTRAINT farms_org_id_key UNIQUE (organization_id, id),
    CONSTRAINT farms_organization_fkey FOREIGN KEY (organization_id)
        REFERENCES public.organizations(id) ON DELETE CASCADE,
    CONSTRAINT farms_name_nonempty CHECK (length(btrim(name)) BETWEEN 1 AND 160),
    CONSTRAINT farms_area_nonnegative CHECK (area_m2 IS NULL OR area_m2 >= 0),
    CONSTRAINT farms_timezone_nonempty CHECK (length(btrim(timezone)) BETWEEN 1 AND 64)
);
CREATE INDEX farms_organization_status_idx ON public.farms(organization_id, status);

CREATE TABLE public.farm_grants (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL,
    membership_id UUID NOT NULL,
    farm_id UUID NOT NULL,
    role public.farm_grant_role NOT NULL,
    version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
    created_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT farm_grants_pkey PRIMARY KEY (id),
    CONSTRAINT farm_grants_org_member_farm_key UNIQUE (organization_id, membership_id, farm_id),
    CONSTRAINT farm_grants_membership_fkey FOREIGN KEY (organization_id, membership_id)
        REFERENCES public.organization_memberships(organization_id, id) ON DELETE CASCADE,
    CONSTRAINT farm_grants_farm_fkey FOREIGN KEY (organization_id, farm_id)
        REFERENCES public.farms(organization_id, id) ON DELETE CASCADE
);

CREATE TABLE public.organization_invitations (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL,
    operation_id UUID NOT NULL,
    email_hash CHAR(64) NOT NULL CHECK (email_hash ~ '^[a-f0-9]{64}$'),
    token_hash CHAR(64) NOT NULL UNIQUE CHECK (token_hash ~ '^[a-f0-9]{64}$'),
    role public.organization_role NOT NULL CHECK (role <> 'owner'),
    created_by_user_id TEXT NOT NULL,
    expires_at TIMESTAMPTZ(6) NOT NULL,
    accepted_at TIMESTAMPTZ(6),
    accepted_by_user_id TEXT,
    accept_operation_id UUID,
    revoked_at TIMESTAMPTZ(6),
    created_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT organization_invitations_pkey PRIMARY KEY (id),
    CONSTRAINT organization_invitations_org_id_key UNIQUE (organization_id, id),
    CONSTRAINT organization_invitations_operation_key UNIQUE (organization_id, created_by_user_id, operation_id),
    CONSTRAINT organization_invitations_org_fkey FOREIGN KEY (organization_id)
        REFERENCES public.organizations(id) ON DELETE CASCADE,
    CONSTRAINT organization_invitations_creator_fkey FOREIGN KEY (created_by_user_id)
        REFERENCES auth."user"(id) ON DELETE RESTRICT,
    CONSTRAINT organization_invitations_acceptor_fkey FOREIGN KEY (accepted_by_user_id)
        REFERENCES auth."user"(id) ON DELETE RESTRICT,
    CONSTRAINT organization_invitations_acceptance_pair CHECK ((accepted_by_user_id IS NULL) = (accept_operation_id IS NULL)),
    CONSTRAINT organization_invitations_expiry_order CHECK (expires_at > created_at)
);
CREATE INDEX organization_invitations_org_expiry_idx ON public.organization_invitations(organization_id, expires_at);
CREATE UNIQUE INDEX organization_invitations_accept_operation_key
    ON public.organization_invitations(accepted_by_user_id, accept_operation_id)
    WHERE accepted_by_user_id IS NOT NULL AND accept_operation_id IS NOT NULL;

CREATE TABLE public.invitation_farm_grants (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL,
    invitation_id UUID NOT NULL,
    farm_id UUID NOT NULL,
    role public.farm_grant_role NOT NULL,
    CONSTRAINT invitation_farm_grants_pkey PRIMARY KEY (id),
    CONSTRAINT invitation_farm_grants_org_invite_farm_key UNIQUE (organization_id, invitation_id, farm_id),
    CONSTRAINT invitation_farm_grants_invitation_fkey FOREIGN KEY (organization_id, invitation_id)
        REFERENCES public.organization_invitations(organization_id, id) ON DELETE CASCADE,
    CONSTRAINT invitation_farm_grants_farm_fkey FOREIGN KEY (organization_id, farm_id)
        REFERENCES public.farms(organization_id, id) ON DELETE CASCADE
);

CREATE TABLE public.organization_creation_receipts (
    actor_id TEXT NOT NULL,
    request_id UUID NOT NULL,
    organization_id UUID NOT NULL UNIQUE,
    created_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT organization_creation_receipts_pkey PRIMARY KEY (actor_id, request_id),
    CONSTRAINT organization_creation_receipts_actor_fkey FOREIGN KEY (actor_id)
        REFERENCES auth."user"(id) ON DELETE RESTRICT,
    CONSTRAINT organization_creation_receipts_org_fkey FOREIGN KEY (organization_id)
        REFERENCES public.organizations(id) ON DELETE CASCADE
);

CREATE FUNCTION public.enforce_last_active_organization_owner() RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
DECLARE
    organization_state public.organization_status;
    other_active_owners BIGINT;
BEGIN
    SELECT status INTO organization_state
      FROM public.organizations
     WHERE id = OLD.organization_id
     FOR UPDATE;

    IF organization_state = 'active'
       AND OLD.role = 'owner'
       AND OLD.status = 'active'
       AND (TG_OP = 'DELETE' OR NEW.role <> 'owner' OR NEW.status <> 'active') THEN
        SELECT count(*) INTO other_active_owners
          FROM public.organization_memberships
         WHERE organization_id = OLD.organization_id
           AND id <> OLD.id
           AND role = 'owner'
           AND status = 'active';
        IF other_active_owners < 1 THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'organization requires an active owner';
        END IF;
    END IF;

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER organization_membership_owner_guard
BEFORE UPDATE OF role, status OR DELETE ON public.organization_memberships
FOR EACH ROW EXECUTE FUNCTION public.enforce_last_active_organization_owner();

CREATE FUNCTION public.create_organization_for_verified_principal(
    p_actor_id TEXT,
    p_request_id UUID,
    p_name TEXT
) RETURNS TABLE(organization_id UUID, membership_id UUID, policy_version BIGINT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
    verified BOOLEAN;
    normalized_name TEXT;
    new_organization_id UUID := gen_random_uuid();
    new_membership_id UUID := gen_random_uuid();
BEGIN
    normalized_name := btrim(p_name);
    IF p_actor_id IS NULL OR p_request_id IS NULL OR normalized_name IS NULL
       OR length(normalized_name) < 1 OR length(normalized_name) > 160 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid organization creation request';
    END IF;

    IF current_setting('app.actor_id', true) IS DISTINCT FROM p_actor_id THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'verified principal required';
    END IF;

    SELECT "emailVerified" INTO verified FROM auth."user" WHERE id = p_actor_id;
    IF NOT COALESCE(verified, FALSE) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'verified principal required';
    END IF;

    INSERT INTO public.organizations(id, name) VALUES (new_organization_id, normalized_name);
    INSERT INTO public.organization_memberships(id, organization_id, user_id, role, status)
    VALUES (new_membership_id, new_organization_id, p_actor_id, 'owner', 'active');
    INSERT INTO public.organization_creation_receipts(actor_id, request_id, organization_id)
    VALUES (p_actor_id, p_request_id, new_organization_id);

    RETURN QUERY SELECT new_organization_id, new_membership_id, 1::BIGINT;
END;
$$;

CREATE FUNCTION public.list_my_organizations(
    p_actor_id TEXT,
    p_limit INTEGER,
    p_after_id UUID DEFAULT NULL
) RETURNS TABLE(
    organization_id UUID,
    organization_name VARCHAR(160),
    organization_status public.organization_status,
    policy_version BIGINT,
    membership_role public.organization_role,
    membership_version INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF p_actor_id IS NULL OR current_setting('app.actor_id', true) IS DISTINCT FROM p_actor_id THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'verified principal required';
    END IF;
    IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid organization page size';
    END IF;

    RETURN QUERY
    SELECT o.id, o.name, o.status, o.policy_version, m.role, m.version
      FROM public.organization_memberships AS m
      JOIN public.organizations AS o ON o.id = m.organization_id
     WHERE m.user_id = p_actor_id
       AND m.status = 'active'
       AND (p_after_id IS NULL OR o.id > p_after_id)
     ORDER BY o.id
     LIMIT p_limit + 1;
END;
$$;

REVOKE ALL ON FUNCTION public.create_organization_for_verified_principal(TEXT, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_organization_for_verified_principal(TEXT, UUID, TEXT) TO farmly_tenant_app;
REVOKE ALL ON FUNCTION public.list_my_organizations(TEXT, INTEGER, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_my_organizations(TEXT, INTEGER, UUID) TO farmly_tenant_app;
REVOKE ALL ON FUNCTION public.enforce_last_active_organization_owner() FROM PUBLIC;
