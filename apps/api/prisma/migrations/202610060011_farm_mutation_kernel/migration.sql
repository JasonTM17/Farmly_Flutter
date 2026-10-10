CREATE TABLE public.farm_clocks (
    organization_id UUID NOT NULL,
    farm_id UUID NOT NULL,
    continuity_epoch BIGINT NOT NULL CHECK (continuity_epoch >= 1),
    revision BIGINT NOT NULL CHECK (revision >= 1),
    pruned_through_revision BIGINT NOT NULL DEFAULT 0 CHECK (pruned_through_revision >= 0),
    created_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT farm_clocks_pkey PRIMARY KEY (organization_id, farm_id),
    CONSTRAINT farm_clocks_floor_lte_revision CHECK (pruned_through_revision <= revision),
    CONSTRAINT farm_clocks_farm_fkey FOREIGN KEY (organization_id, farm_id)
        REFERENCES public.farms(organization_id, id) ON DELETE CASCADE
);

CREATE TABLE public.applied_operations (
    organization_id UUID NOT NULL,
    actor_pseudonym CHAR(64) NOT NULL CHECK (actor_pseudonym ~ '^[a-f0-9]{64}$'),
    operation_id UUID NOT NULL,
    request_hash CHAR(64) NOT NULL CHECK (request_hash ~ '^[a-f0-9]{64}$'),
    continuity_epoch BIGINT NOT NULL CHECK (continuity_epoch >= 1),
    outcome TEXT NOT NULL CHECK (outcome IN ('pending', 'applied', 'rejected')),
    result_code TEXT,
    resource_id UUID,
    result_version INTEGER,
    created_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ(6),
    CONSTRAINT applied_operations_pkey PRIMARY KEY (organization_id, actor_pseudonym, operation_id),
    CONSTRAINT applied_operations_org_fkey FOREIGN KEY (organization_id)
        REFERENCES public.organizations(id) ON DELETE CASCADE,
    CONSTRAINT applied_operations_farm_fkey FOREIGN KEY (organization_id, resource_id)
        REFERENCES public.farms(organization_id, id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT applied_operations_terminal_state CHECK (
        (outcome = 'pending' AND completed_at IS NULL)
        OR (outcome IN ('applied', 'rejected') AND completed_at IS NOT NULL)
    ),
    CONSTRAINT applied_operations_result_version CHECK (result_version IS NULL OR result_version >= 1)
);

CREATE INDEX applied_operations_operation_lookup_idx
    ON public.applied_operations (actor_pseudonym, operation_id);

CREATE TABLE public.operation_response_cache (
    organization_id UUID NOT NULL,
    actor_pseudonym CHAR(64) NOT NULL,
    operation_id UUID NOT NULL,
    response_data JSONB NOT NULL,
    created_at TIMESTAMPTZ(6) NOT NULL,
    expires_at TIMESTAMPTZ(6) NOT NULL,
    CONSTRAINT operation_response_cache_pkey PRIMARY KEY (organization_id, actor_pseudonym, operation_id),
    CONSTRAINT operation_response_cache_expiry_order CHECK (expires_at > created_at),
    CONSTRAINT operation_response_cache_operation_fkey FOREIGN KEY (organization_id, actor_pseudonym, operation_id)
        REFERENCES public.applied_operations(organization_id, actor_pseudonym, operation_id) ON DELETE CASCADE
);
CREATE INDEX operation_response_cache_expiry_idx ON public.operation_response_cache (expires_at);

CREATE TABLE public.change_sets (
    organization_id UUID NOT NULL,
    farm_id UUID NOT NULL,
    revision BIGINT NOT NULL CHECK (revision >= 1),
    continuity_epoch BIGINT NOT NULL CHECK (continuity_epoch >= 1),
    actor_pseudonym CHAR(64) NOT NULL CHECK (actor_pseudonym ~ '^[a-f0-9]{64}$'),
    operation_id UUID NOT NULL,
    schema_version TEXT NOT NULL CHECK (length(schema_version) BETWEEN 1 AND 64),
    changes JSONB NOT NULL CHECK (jsonb_typeof(changes) = 'array' AND jsonb_array_length(changes) >= 1),
    created_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT change_sets_pkey PRIMARY KEY (organization_id, farm_id, revision),
    CONSTRAINT change_sets_operation_key UNIQUE (organization_id, actor_pseudonym, operation_id),
    CONSTRAINT change_sets_clock_fkey FOREIGN KEY (organization_id, farm_id)
        REFERENCES public.farm_clocks(organization_id, farm_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT change_sets_operation_fkey FOREIGN KEY (organization_id, actor_pseudonym, operation_id)
        REFERENCES public.applied_operations(organization_id, actor_pseudonym, operation_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
CREATE INDEX change_sets_feed_idx ON public.change_sets (organization_id, farm_id, revision);

CREATE TABLE public.audit_events (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL,
    farm_id UUID NOT NULL,
    actor_pseudonym CHAR(64) NOT NULL CHECK (actor_pseudonym ~ '^[a-f0-9]{64}$'),
    operation_id UUID NOT NULL,
    action TEXT NOT NULL CHECK (length(action) BETWEEN 1 AND 80),
    revision BIGINT NOT NULL CHECK (revision >= 1),
    details JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(details) = 'object'),
    created_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT audit_events_pkey PRIMARY KEY (id),
    CONSTRAINT audit_events_operation_key UNIQUE (organization_id, actor_pseudonym, operation_id),
    CONSTRAINT audit_events_org_fkey FOREIGN KEY (organization_id)
        REFERENCES public.organizations(id) ON DELETE CASCADE,
    CONSTRAINT audit_events_farm_fkey FOREIGN KEY (organization_id, farm_id)
        REFERENCES public.farms(organization_id, id) ON DELETE CASCADE,
    CONSTRAINT audit_events_operation_fkey FOREIGN KEY (organization_id, actor_pseudonym, operation_id)
        REFERENCES public.applied_operations(organization_id, actor_pseudonym, operation_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
CREATE INDEX audit_events_org_created_idx ON public.audit_events (organization_id, created_at DESC);

ALTER TABLE public.farm_clocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.farm_clocks FORCE ROW LEVEL SECURITY;
CREATE POLICY farm_clocks_migration_access ON public.farm_clocks
    TO farmly_migration USING (TRUE) WITH CHECK (TRUE);

ALTER TABLE public.applied_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.applied_operations FORCE ROW LEVEL SECURITY;
CREATE POLICY applied_operations_migration_access ON public.applied_operations
    TO farmly_migration USING (TRUE) WITH CHECK (TRUE);

ALTER TABLE public.operation_response_cache ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.operation_response_cache FORCE ROW LEVEL SECURITY;
CREATE POLICY operation_response_cache_migration_access ON public.operation_response_cache
    TO farmly_migration USING (TRUE) WITH CHECK (TRUE);

ALTER TABLE public.change_sets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.change_sets FORCE ROW LEVEL SECURITY;
CREATE POLICY change_sets_migration_access ON public.change_sets
    TO farmly_migration USING (TRUE) WITH CHECK (TRUE);

ALTER TABLE public.audit_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_events FORCE ROW LEVEL SECURITY;
CREATE POLICY audit_events_migration_access ON public.audit_events
    TO farmly_migration USING (TRUE) WITH CHECK (TRUE);

REVOKE ALL PRIVILEGES ON TABLE
    public.farm_clocks,
    public.applied_operations,
    public.operation_response_cache,
    public.change_sets,
    public.audit_events
FROM PUBLIC, farmly_auth_app, farmly_tenant_app;

CREATE FUNCTION public.apply_farm_mutation(
    p_organization_id UUID,
    p_actor_id TEXT,
    p_actor_pseudonym TEXT,
    p_operation_id UUID,
    p_request_hash TEXT,
    p_continuity_epoch BIGINT,
    p_intent JSONB,
    p_forced_rejection_code TEXT DEFAULT NULL
) RETURNS TABLE(
    outcome TEXT,
    code TEXT,
    response_data JSONB,
    scope_policy_version BIGINT,
    continuity_epoch BIGINT,
    replayed BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_organization_status public.organization_status;
    v_scope_policy_version BIGINT;
    v_current_epoch BIGINT;
    v_actor_role public.organization_role;
    v_existing_hash CHAR(64);
    v_existing_epoch BIGINT;
    v_existing_outcome TEXT;
    v_existing_code TEXT;
    v_existing_resource_id UUID;
    v_cached_data JSONB;
    v_rejection_code TEXT;
    v_payload JSONB;
    v_resource_id UUID;
    v_name TEXT;
    v_timezone TEXT;
    v_area NUMERIC(14, 2);
    v_revision BIGINT := 1;
    v_created_at TIMESTAMPTZ(6);
    v_farm_data JSONB;
    v_result_data JSONB;
BEGIN
    IF p_actor_id IS NULL OR NULLIF(current_setting('app.actor_id', TRUE), '') IS DISTINCT FROM p_actor_id THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'FARMLY_PERMISSION_DENIED';
    END IF;
    IF p_organization_id IS NULL OR p_operation_id IS NULL
       OR p_actor_pseudonym IS NULL OR p_actor_pseudonym !~ '^[a-f0-9]{64}$'
       OR p_request_hash IS NULL OR p_request_hash !~ '^[a-f0-9]{64}$'
       OR p_continuity_epoch IS NULL OR p_continuity_epoch < 1
       OR p_intent IS NULL OR jsonb_typeof(p_intent) IS DISTINCT FROM 'object'
       OR (p_intent - 'schemaVersion' - 'continuityEpoch' - 'operationId' - 'type'
           - 'resourceId' - 'baseVersion' - 'dependsOn' - 'payload') <> '{}'::JSONB THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid mutation envelope';
    END IF;

    SELECT organization.status, organization.policy_version, organization.continuity_epoch
      INTO v_organization_status, v_scope_policy_version, v_current_epoch
      FROM public.organizations AS organization
     WHERE organization.id = p_organization_id
     FOR UPDATE;
    IF NOT FOUND OR v_organization_status <> 'active' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'FARMLY_ACCESS_REVOKED';
    END IF;

    SELECT membership.role
      INTO v_actor_role
      FROM public.organization_memberships AS membership
     WHERE membership.organization_id = p_organization_id
       AND membership.user_id = p_actor_id
       AND membership.status = 'active';
    IF v_actor_role IS NULL OR v_actor_role NOT IN ('owner', 'admin') THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'FARMLY_PERMISSION_DENIED';
    END IF;

    IF p_intent ->> 'operationId' IS DISTINCT FROM p_operation_id::TEXT THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'operation identity mismatch';
    END IF;

    IF p_continuity_epoch <> v_current_epoch
       OR p_intent ->> 'continuityEpoch' IS DISTINCT FROM v_current_epoch::TEXT THEN
        RETURN QUERY SELECT 'conflict'::TEXT, 'RECONCILIATION_REQUIRED'::TEXT,
            jsonb_build_object('operationId', p_operation_id, 'outcome', 'conflict'),
            v_scope_policy_version, v_current_epoch, FALSE;
        RETURN;
    END IF;

    SELECT operation.request_hash, operation.continuity_epoch, operation.outcome,
           operation.result_code, operation.resource_id
      INTO v_existing_hash, v_existing_epoch, v_existing_outcome, v_existing_code, v_existing_resource_id
      FROM public.applied_operations AS operation
     WHERE operation.organization_id = p_organization_id
       AND operation.actor_pseudonym = p_actor_pseudonym
       AND operation.operation_id = p_operation_id;
    IF FOUND THEN
        IF v_existing_hash IS DISTINCT FROM p_request_hash THEN
            RETURN QUERY SELECT 'conflict'::TEXT, 'OPERATION_ID_REUSED'::TEXT,
                jsonb_build_object('operationId', p_operation_id, 'outcome', 'conflict'),
                v_scope_policy_version, v_current_epoch, FALSE;
            RETURN;
        END IF;
        IF v_existing_epoch <> v_current_epoch THEN
            RETURN QUERY SELECT 'conflict'::TEXT, 'RECONCILIATION_REQUIRED'::TEXT,
                jsonb_build_object('operationId', p_operation_id, 'outcome', 'conflict'),
                v_scope_policy_version, v_current_epoch, FALSE;
            RETURN;
        END IF;

        SELECT cache.response_data
          INTO v_cached_data
          FROM public.operation_response_cache AS cache
         WHERE cache.organization_id = p_organization_id
           AND cache.actor_pseudonym = p_actor_pseudonym
           AND cache.operation_id = p_operation_id
           AND cache.expires_at > clock_timestamp();
        IF FOUND THEN
            RETURN QUERY SELECT v_existing_outcome, v_existing_code, v_cached_data,
                v_scope_policy_version, v_current_epoch, TRUE;
        ELSE
            RETURN QUERY SELECT v_existing_outcome, v_existing_code,
                jsonb_build_object('operationId', p_operation_id, 'outcome', v_existing_outcome, 'replayed', TRUE),
                v_scope_policy_version, v_current_epoch, TRUE;
        END IF;
        RETURN;
    END IF;

    v_rejection_code := p_forced_rejection_code;
    IF v_rejection_code IS NOT NULL AND v_rejection_code NOT IN (
        'MUTATION_NOT_SUPPORTED', 'FIELD_VALIDATION_FAILED', 'DEPENDENCY_NOT_APPLIED'
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid internal rejection code';
    END IF;
    IF v_rejection_code IS NULL AND p_intent ->> 'type' IS DISTINCT FROM 'farm.create' THEN
        v_rejection_code := 'MUTATION_NOT_SUPPORTED';
    END IF;

    v_payload := p_intent -> 'payload';
    IF v_rejection_code IS NULL THEN
        IF p_intent ->> 'schemaVersion' IS DISTINCT FROM 'farm-mutation.v1'
           OR jsonb_typeof(v_payload) IS DISTINCT FROM 'object'
           OR (v_payload - 'name' - 'areaM2' - 'timezone') <> '{}'::JSONB
           OR jsonb_typeof(p_intent -> 'dependsOn') IS DISTINCT FROM 'array'
           OR (p_intent ? 'baseVersion' AND p_intent -> 'baseVersion' NOT IN ('null'::JSONB)) THEN
            v_rejection_code := 'FIELD_VALIDATION_FAILED';
        ELSE
            v_name := btrim(v_payload ->> 'name');
            v_timezone := btrim(v_payload ->> 'timezone');
            IF v_name IS NULL OR length(v_name) < 1 OR length(v_name) > 160
               OR v_timezone IS NULL OR length(v_timezone) < 1 OR length(v_timezone) > 64
               OR (v_payload ? 'areaM2' AND (
                   jsonb_typeof(v_payload -> 'areaM2') IS DISTINCT FROM 'string'
                   OR (v_payload ->> 'areaM2') !~ '^(0|[1-9][0-9]{0,11})(\.[0-9]{1,2})?$'
               )) THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSE
                IF v_payload ? 'areaM2' THEN v_area := (v_payload ->> 'areaM2')::NUMERIC(14, 2); END IF;
                v_resource_id := (p_intent ->> 'resourceId')::UUID;
            END IF;
        END IF;
    END IF;

    IF v_rejection_code IS NULL AND EXISTS (
        SELECT 1
          FROM jsonb_array_elements_text(p_intent -> 'dependsOn') AS dependency(operation_id)
          LEFT JOIN public.applied_operations AS parent
            ON parent.organization_id = p_organization_id
           AND parent.actor_pseudonym = p_actor_pseudonym
           AND parent.operation_id = dependency.operation_id::UUID
           AND parent.continuity_epoch = v_current_epoch
           AND parent.outcome = 'applied'
         WHERE parent.operation_id IS NULL
    ) THEN
        v_rejection_code := 'DEPENDENCY_NOT_APPLIED';
    END IF;

    IF v_rejection_code IS NOT NULL THEN
        v_created_at := clock_timestamp();
        v_result_data := jsonb_build_object('operationId', p_operation_id, 'outcome', 'rejected', 'code', v_rejection_code);
        INSERT INTO public.applied_operations (
            organization_id, actor_pseudonym, operation_id, request_hash, continuity_epoch,
            outcome, result_code, resource_id, created_at, completed_at
        ) VALUES (
            p_organization_id, p_actor_pseudonym, p_operation_id, p_request_hash, v_current_epoch,
            'rejected', v_rejection_code, NULL, v_created_at, v_created_at
        );
        INSERT INTO public.operation_response_cache (
            organization_id, actor_pseudonym, operation_id, response_data, created_at, expires_at
        ) VALUES (
            p_organization_id, p_actor_pseudonym, p_operation_id, v_result_data, v_created_at,
            v_created_at + INTERVAL '7 days'
        );
        RETURN QUERY SELECT 'rejected'::TEXT, v_rejection_code, v_result_data,
            v_scope_policy_version, v_current_epoch, FALSE;
        RETURN;
    END IF;

    v_created_at := clock_timestamp();
    INSERT INTO public.applied_operations (
        organization_id, actor_pseudonym, operation_id, request_hash, continuity_epoch,
        outcome, resource_id, result_version, created_at
    ) VALUES (
        p_organization_id, p_actor_pseudonym, p_operation_id, p_request_hash, v_current_epoch,
        'pending', v_resource_id, 1, v_created_at
    );

    INSERT INTO public.farms (
        id, organization_id, name, area_m2, timezone, status, version, created_at, updated_at
    ) VALUES (
        v_resource_id, p_organization_id, v_name, v_area, v_timezone, 'active', 1, v_created_at, v_created_at
    );
    INSERT INTO public.farm_clocks (
        organization_id, farm_id, continuity_epoch, revision, pruned_through_revision, created_at, updated_at
    ) VALUES (
        p_organization_id, v_resource_id, v_current_epoch, v_revision, 0, v_created_at, v_created_at
    );
    UPDATE public.organizations
       SET policy_version = policy_version + 1,
           updated_at = v_created_at
     WHERE id = p_organization_id
     RETURNING policy_version INTO v_scope_policy_version;

    v_farm_data := jsonb_build_object(
        'farmId', v_resource_id,
        'name', v_name,
        'areaM2', CASE WHEN v_area IS NULL THEN NULL ELSE v_area::TEXT END,
        'timezone', v_timezone,
        'status', 'active',
        'version', 1
    );
    INSERT INTO public.change_sets (
        organization_id, farm_id, revision, continuity_epoch, actor_pseudonym,
        operation_id, schema_version, changes, created_at
    ) VALUES (
        p_organization_id, v_resource_id, v_revision, v_current_epoch, p_actor_pseudonym,
        p_operation_id, 'farm-change-set.v1',
        jsonb_build_array(jsonb_build_object('entity', 'farm', 'change', 'upsert', 'record', v_farm_data)),
        v_created_at
    );
    INSERT INTO public.audit_events (
        organization_id, farm_id, actor_pseudonym, operation_id, action, revision, details, created_at
    ) VALUES (
        p_organization_id, v_resource_id, p_actor_pseudonym, p_operation_id,
        'farm.create', v_revision, jsonb_build_object('version', 1), v_created_at
    );

    v_result_data := jsonb_build_object(
        'operationId', p_operation_id,
        'outcome', 'applied',
        'farm', v_farm_data,
        'revision', v_revision::TEXT
    );
    UPDATE public.applied_operations
       SET outcome = 'applied', completed_at = v_created_at
     WHERE organization_id = p_organization_id
       AND actor_pseudonym = p_actor_pseudonym
       AND operation_id = p_operation_id;
    INSERT INTO public.operation_response_cache (
        organization_id, actor_pseudonym, operation_id, response_data, created_at, expires_at
    ) VALUES (
        p_organization_id, p_actor_pseudonym, p_operation_id, v_result_data, v_created_at,
        v_created_at + INTERVAL '7 days'
    );

    RETURN QUERY SELECT 'applied'::TEXT, NULL::TEXT, v_result_data,
        v_scope_policy_version, v_current_epoch, FALSE;
END;
$$;

CREATE FUNCTION public.get_my_operation_status(
    p_actor_id TEXT,
    p_actor_pseudonym TEXT,
    p_operation_ids UUID[]
) RETURNS TABLE(operation_id UUID, outcome TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF p_actor_id IS NULL OR NULLIF(current_setting('app.actor_id', TRUE), '') IS DISTINCT FROM p_actor_id
       OR p_actor_pseudonym IS NULL OR p_actor_pseudonym !~ '^[a-f0-9]{64}$'
       OR p_operation_ids IS NULL OR cardinality(p_operation_ids) < 1 OR cardinality(p_operation_ids) > 50 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid operation status request';
    END IF;

    RETURN QUERY
    SELECT requested.operation_id,
           COALESCE((
               SELECT CASE
                        WHEN count(*) = 1
                         AND bool_and(organization.continuity_epoch = operation.continuity_epoch)
                         AND bool_and(operation.outcome IN ('applied', 'rejected'))
                          THEN (array_agg(operation.outcome))[1]
                        ELSE 'unknown'
                      END::TEXT
                 FROM public.applied_operations AS operation
                 LEFT JOIN public.organizations AS organization
                   ON organization.id = operation.organization_id
                WHERE operation.actor_pseudonym = p_actor_pseudonym
                  AND operation.operation_id = requested.operation_id
           ), 'unknown'::TEXT)
      FROM unnest(p_operation_ids) WITH ORDINALITY AS requested(operation_id, ordinal)
     ORDER BY requested.ordinal;
END;
$$;

REVOKE ALL ON FUNCTION public.apply_farm_mutation(UUID, TEXT, TEXT, UUID, TEXT, BIGINT, JSONB, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.apply_farm_mutation(UUID, TEXT, TEXT, UUID, TEXT, BIGINT, JSONB, TEXT) TO farmly_tenant_app;
REVOKE ALL ON FUNCTION public.get_my_operation_status(TEXT, TEXT, UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_operation_status(TEXT, TEXT, UUID[]) TO farmly_tenant_app;
