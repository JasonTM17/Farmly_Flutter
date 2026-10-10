-- P07 farm location + weather snapshot cache.
--
-- Repair-forward migration (checksum ledger forbids editing applied files):
--   1. farms.location — optional coarse weather grid "lat,lon" with EXACTLY one
--      decimal digit each (0.1 degree ~ 11 km). The CHECK via
--      farmly_is_coarse_grid makes exact coordinates unrepresentable (P-05).
--   2. weather_snapshots — provider response cache, farm-scoped. Explicitly
--      outside the domain changefeed (spec04): read model serves latest row +
--      derived fresh/stale/unavailable; a refresh job writes via
--      farmly_record_weather_snapshot (SECURITY DEFINER) as farmly_tenant_app.
--   3. apply_farm_mutation redeclared with `location` support in
--      farm.create / farm.update payloads and farm views.

CREATE OR REPLACE FUNCTION public.farmly_is_coarse_grid(value TEXT) RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT value IS NOT NULL
       AND value ~ '^-?[0-9]{1,2}\.[0-9],-?[0-9]{1,3}\.[0-9]$'
       AND split_part(value, ',', 1)::NUMERIC BETWEEN -90 AND 90
       AND split_part(value, ',', 2)::NUMERIC BETWEEN -180 AND 180;
$$;

REVOKE ALL ON FUNCTION public.farmly_is_coarse_grid(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.farmly_is_coarse_grid(TEXT) TO farmly_tenant_app;

ALTER TABLE public.farms ADD COLUMN location VARCHAR(40);
ALTER TABLE public.farms ADD CONSTRAINT farms_location_coarse_grid
    CHECK (location IS NULL OR public.farmly_is_coarse_grid(location));

CREATE TABLE public.weather_snapshots (
    organization_id UUID NOT NULL,
    farm_id UUID NOT NULL,
    id UUID NOT NULL,
    provider VARCHAR(80) NOT NULL CHECK (length(btrim(provider)) BETWEEN 1 AND 80),
    kind TEXT NOT NULL DEFAULT 'current' CHECK (kind IN ('current', 'forecast')),
    grid_ref VARCHAR(40) NOT NULL,
    valid_at TIMESTAMPTZ(6) NOT NULL,
    fetched_at TIMESTAMPTZ(6) NOT NULL,
    payload JSONB NOT NULL CHECK (jsonb_typeof(payload) = 'object'),
    created_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT weather_snapshots_pkey PRIMARY KEY (organization_id, farm_id, id),
    CONSTRAINT weather_snapshots_farm_fkey FOREIGN KEY (organization_id, farm_id)
        REFERENCES public.farms(organization_id, id) ON DELETE CASCADE
);

CREATE INDEX weather_snapshots_farm_kind_fetched_idx
    ON public.weather_snapshots (organization_id, farm_id, kind, fetched_at DESC);

ALTER TABLE public.weather_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.weather_snapshots FORCE ROW LEVEL SECURITY;
CREATE POLICY weather_snapshots_migration_access ON public.weather_snapshots
    TO farmly_migration USING (TRUE) WITH CHECK (TRUE);
CREATE POLICY weather_snapshots_tenant_read ON public.weather_snapshots
    FOR SELECT TO farmly_tenant_app
    USING (public.farmly_actor_can_read_farm(organization_id, farm_id));

REVOKE ALL PRIVILEGES ON TABLE public.weather_snapshots FROM PUBLIC, farmly_auth_app, farmly_tenant_app;
GRANT SELECT ON TABLE public.weather_snapshots TO farmly_tenant_app;

-- Cache writes go through a narrow SECURITY DEFINER writer: it binds the row to
-- the farm's configured coarse grid (no caller-chosen location, no IDs leave or
-- enter) and validates the provider payload shape. farmly_tenant_app can call it
-- but cannot write the table directly, so a tenant session cannot forge a
-- snapshot the provider never delivered.
CREATE FUNCTION public.farmly_record_weather_snapshot(
    p_organization_id UUID,
    p_farm_id UUID,
    p_provider VARCHAR(80),
    p_grid_ref VARCHAR(40),
    p_valid_at TIMESTAMPTZ(6),
    p_payload JSONB
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_location VARCHAR(40);
    v_id UUID := gen_random_uuid();
BEGIN
    SELECT farm.location INTO v_location
      FROM public.farms AS farm
     WHERE farm.organization_id = p_organization_id
       AND farm.id = p_farm_id
       AND farm.status = 'active';
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'FARMLY_ACCESS_REVOKED';
    END IF;
    IF v_location IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'FARMLY_WEATHER_NO_LOCATION';
    END IF;
    IF v_location IS DISTINCT FROM p_grid_ref THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'FARMLY_WEATHER_GRID_MISMATCH';
    END IF;
    IF p_provider IS NULL OR length(btrim(p_provider)) < 1 OR length(p_provider) > 80
       OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object'
       OR jsonb_typeof(p_payload -> 'temperatureC') IS DISTINCT FROM 'number'
       OR jsonb_typeof(p_payload -> 'weatherCode') IS DISTINCT FROM 'number'
       OR p_valid_at IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'FARMLY_WEATHER_PAYLOAD_INVALID';
    END IF;
    INSERT INTO public.weather_snapshots (
        organization_id, farm_id, id, provider, kind, grid_ref,
        valid_at, fetched_at, payload, created_at
    ) VALUES (
        p_organization_id, p_farm_id, v_id, btrim(p_provider), 'current', p_grid_ref,
        p_valid_at, CURRENT_TIMESTAMP, p_payload, CURRENT_TIMESTAMP
    );
    RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.farmly_record_weather_snapshot(UUID, UUID, VARCHAR, VARCHAR, TIMESTAMPTZ, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.farmly_record_weather_snapshot(UUID, UUID, VARCHAR, VARCHAR, TIMESTAMPTZ, JSONB) TO farmly_tenant_app;

CREATE OR REPLACE FUNCTION public.apply_farm_mutation(
    p_organization_id UUID,
    p_actor_id TEXT,
    p_actor_pseudonym TEXT,
    p_operation_id UUID,
    p_request_hash TEXT,
    p_continuity_epoch BIGINT,
    p_intent JSONB,
    p_forced_rejection_code TEXT DEFAULT NULL,
    p_farm_id UUID DEFAULT NULL
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
    v_membership_id UUID;
    v_existing_hash CHAR(64);
    v_existing_epoch BIGINT;
    v_existing_outcome TEXT;
    v_existing_code TEXT;
    v_existing_resource_id UUID;
    v_cached_data JSONB;
    v_rejection_code TEXT;
    v_conflict_code TEXT;
    v_payload JSONB;
    v_type TEXT;
    v_resource_id UUID;
    v_base_version INTEGER;
    v_name TEXT;
    v_timezone TEXT;
    v_area NUMERIC(14, 2);
    v_location VARCHAR(40);
    v_revision BIGINT := 1;
    v_created_at TIMESTAMPTZ(6);
    v_farm RECORD;
    v_row RECORD;
    v_view JSONB;
    v_view_key TEXT;
    v_headcount INTEGER;
    v_result_data JSONB;
    v_date DATE;
    v_capacity NUMERIC(20, 4);
    v_farm_write TEXT;
    v_qty NUMERIC(20, 4);
    v_slot TEXT;
    v_occ_date DATE;
    v_det_id UUID;
    v_hash TEXT;
    v_transition TEXT;
    v_from_status TEXT;
    v_to_status TEXT;
    v_occ RECORD;
    v_head RECORD;
    v_proposal RECORD;
    v_changes JSONB;
    v_measured TIMESTAMPTZ(6);
    v_record_id UUID;
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
    v_type := p_intent ->> 'type';

    SELECT organization.status, organization.policy_version, organization.continuity_epoch
      INTO v_organization_status, v_scope_policy_version, v_current_epoch
      FROM public.organizations AS organization
     WHERE organization.id = p_organization_id
     FOR UPDATE;
    IF NOT FOUND OR v_organization_status <> 'active' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'FARMLY_ACCESS_REVOKED';
    END IF;

    SELECT membership.role, membership.id
      INTO v_actor_role, v_membership_id
      FROM public.organization_memberships AS membership
     WHERE membership.organization_id = p_organization_id
       AND membership.user_id = p_actor_id
       AND membership.status = 'active';
    IF v_actor_role IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'FARMLY_PERMISSION_DENIED';
    END IF;

    IF p_farm_id IS NULL THEN
        IF v_actor_role NOT IN ('owner', 'admin') THEN
            RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'FARMLY_PERMISSION_DENIED';
        END IF;
    ELSE
        -- Farm-scoped writes: org owner/admin, or an org member holding an
        -- owner/admin/manager grant on this farm. Org viewers are read-only
        -- even with a stale elevated grant (spec01 role table).
        -- Resolve the effective farm write level: org owner/admin act as
        -- manager; an org member writes through their strongest farm grant.
        -- Org viewers stay read-only even with a stale grant. Workers may
        -- write only the operational-fact op set (spec04 section 5.2).
        v_farm_write := NULL;
        IF v_actor_role IN ('owner', 'admin') THEN
            v_farm_write := 'manager';
        ELSIF v_actor_role = 'member' THEN
            -- Only manager/worker grants carry write scope; a viewer grant is
            -- read-only and must never escalate (spec04 section 5.2).
            SELECT (CASE grant_row.role WHEN 'manager' THEN 'manager' ELSE 'worker' END)::TEXT
              INTO v_farm_write
              FROM public.farm_grants AS grant_row
             WHERE grant_row.organization_id = p_organization_id
               AND grant_row.membership_id = v_membership_id
               AND grant_row.farm_id = p_farm_id
               AND grant_row.role IN ('manager', 'worker')
             ORDER BY CASE grant_row.role WHEN 'manager' THEN 1 ELSE 2 END
             LIMIT 1;
        END IF;
        IF v_farm_write IS NULL
           OR (v_farm_write = 'worker' AND v_type NOT IN (
               'plantingEvent.create', 'animalObservation.create',
               'productionRecord.create', 'moistureReading.create',
               'waterReading.create', 'waterUsage.create',
               'harvest.create', 'harvest.correction.propose',
               'taskOccurrence.transition', 'irrigationTask.transition')) THEN
            RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'FARMLY_PERMISSION_DENIED';
        END IF;
        -- Farm profile/archive mutations are org owner/admin only.
        IF v_type IN ('farm.update', 'farm.archive') AND v_actor_role NOT IN ('owner', 'admin') THEN
            RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'FARMLY_PERMISSION_DENIED';
        END IF;
        -- Lock the farm row first (org -> farm -> resource lock order) so the
        -- archive barrier serializes against in-flight domain writes.
        SELECT farm.* INTO v_farm
          FROM public.farms AS farm
         WHERE farm.organization_id = p_organization_id
           AND farm.id = p_farm_id
         FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'FARMLY_SCOPE_UNKNOWN';
        END IF;
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

    -- Scope binding: org-scoped ingress admits farm.create only; the farm-scoped
    -- kernel admits domain/farm lifecycle types and refuses farm.create.
    IF v_rejection_code IS NULL THEN
        IF p_farm_id IS NULL THEN
            IF v_type IS DISTINCT FROM 'farm.create' THEN
                v_rejection_code := 'MUTATION_NOT_SUPPORTED';
            END IF;
        ELSIF v_type IS NULL OR v_type NOT IN (
            'farm.update', 'farm.archive',
            'zone.create', 'zone.update', 'zone.archive',
            'cropSpecies.create', 'cropSpecies.update', 'cropSpecies.archive',
            'planting.create', 'planting.update', 'planting.archive',
            'herd.create', 'herd.update', 'herd.archive',
            'animal.create', 'animal.update', 'animal.archive',
            'waterTank.create', 'waterTank.update', 'waterTank.archive',
            'plantingEvent.create',
            'livestockMovement.create',
            'animalObservation.create',
            'productionRecord.create',
            'taskTemplate.create', 'taskTemplate.update',
            'taskOccurrence.transition', 'irrigationTask.transition',
            'harvest.create', 'harvest.correction.propose',
            'harvest.correction.apply', 'harvest.void',
            'moistureReading.create',
            'waterReading.create',
            'waterUsage.create'
        ) THEN
            v_rejection_code := 'MUTATION_NOT_SUPPORTED';
        END IF;
    END IF;

    -- resourceId must be a well-formed UUID before any cast.
    IF v_rejection_code IS NULL THEN
        IF p_intent ->> 'resourceId' IS NULL
           OR (p_intent ->> 'resourceId') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
            v_rejection_code := 'FIELD_VALIDATION_FAILED';
        ELSE
            v_resource_id := (p_intent ->> 'resourceId')::UUID;
        END IF;
    END IF;

    -- Envelope version rule: creates take baseVersion absent/null; updates and
    -- archives require a positive integer that later matches the row version.
    IF v_rejection_code IS NULL THEN
        IF v_type LIKE '%.create' OR v_type = 'harvest.correction.propose' THEN
            IF p_intent ? 'baseVersion' AND p_intent -> 'baseVersion' <> 'null'::JSONB THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            END IF;
        ELSIF v_type LIKE '%.update' OR v_type LIKE '%.archive'
              OR v_type IN ('harvest.correction.apply', 'harvest.void') THEN
            IF jsonb_typeof(p_intent -> 'baseVersion') IS DISTINCT FROM 'number'
               OR (p_intent ->> 'baseVersion') !~ '^[1-9][0-9]{0,9}$' THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSE
                v_base_version := (p_intent ->> 'baseVersion')::INTEGER;
            END IF;
        ELSIF v_type LIKE '%.transition' THEN
            -- Occurrence may not be materialized yet: baseVersion is optional;
            -- when present it must be a positive integer and the row check
            -- below enforces the CAS.
            IF p_intent ? 'baseVersion' AND p_intent -> 'baseVersion' <> 'null'::JSONB THEN
                IF jsonb_typeof(p_intent -> 'baseVersion') IS DISTINCT FROM 'number'
                   OR (p_intent ->> 'baseVersion') !~ '^[1-9][0-9]{0,9}$' THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSE
                    v_base_version := (p_intent ->> 'baseVersion')::INTEGER;
                END IF;
            END IF;
        END IF;
    END IF;

    -- Deny-after-archive (S-07): an archived farm refuses every operational write.
    -- Nested IF because plpgsql evaluates a record's field eagerly even inside a
    -- short-circuited expression; v_farm is only assigned on the farm-scoped path.
    IF v_rejection_code IS NULL AND p_farm_id IS NOT NULL THEN
        IF v_farm.status <> 'active' THEN
            v_rejection_code := 'RESOURCE_ARCHIVED';
        END IF;
    END IF;

    v_payload := p_intent -> 'payload';

    -- ---- per-type payload validation + CAS row fetch ------------------------
    IF v_rejection_code IS NULL THEN
        IF v_type = 'farm.create' THEN
            IF jsonb_typeof(v_payload) IS DISTINCT FROM 'object'
               OR (v_payload - 'name' - 'areaM2' - 'timezone' - 'location') <> '{}'::JSONB THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSE
                v_name := btrim(v_payload ->> 'name');
                v_timezone := btrim(v_payload ->> 'timezone');
                IF v_name IS NULL OR length(v_name) < 1 OR length(v_name) > 160
                   OR v_timezone IS NULL OR length(v_timezone) < 1 OR length(v_timezone) > 64
                   OR (v_payload ? 'areaM2' AND (
                       jsonb_typeof(v_payload -> 'areaM2') IS DISTINCT FROM 'string'
                       OR (v_payload ->> 'areaM2') !~ '^(0|[1-9][0-9]{0,11})(\.[0-9]{1,2})?$'
                   ))
                   OR (v_payload ? 'location' AND (
                       jsonb_typeof(v_payload -> 'location') IS DISTINCT FROM 'string'
                       OR NOT public.farmly_is_coarse_grid(v_payload ->> 'location')
                   )) THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSE
                    IF v_payload ? 'areaM2' THEN
                        v_area := (v_payload ->> 'areaM2')::NUMERIC(14, 2);
                    END IF;
                    IF v_payload ? 'location' THEN
                        v_location := btrim(v_payload ->> 'location');
                    END IF;
                END IF;
            END IF;

        ELSIF v_type IN ('farm.update', 'farm.archive') THEN
            IF jsonb_typeof(v_payload) IS DISTINCT FROM 'object' THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF v_type = 'farm.archive' AND v_payload <> '{}'::JSONB THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF v_type = 'farm.update' THEN
                IF (v_payload - 'name' - 'timezone' - 'areaM2' - 'location') <> '{}'::JSONB
                   OR v_payload = '{}'::JSONB THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSE
                    IF v_payload ? 'name' THEN
                        v_name := btrim(v_payload ->> 'name');
                        IF v_name IS NULL OR length(v_name) < 1 OR length(v_name) > 160 THEN
                            v_rejection_code := 'FIELD_VALIDATION_FAILED';
                        END IF;
                    END IF;
                    IF v_rejection_code IS NULL AND v_payload ? 'timezone' THEN
                        v_timezone := btrim(v_payload ->> 'timezone');
                        IF v_timezone IS NULL OR length(v_timezone) < 1 OR length(v_timezone) > 64 THEN
                            v_rejection_code := 'FIELD_VALIDATION_FAILED';
                        END IF;
                    END IF;
                    IF v_rejection_code IS NULL AND v_payload ? 'areaM2' THEN
                        IF jsonb_typeof(v_payload -> 'areaM2') IS DISTINCT FROM 'string'
                           OR (v_payload ->> 'areaM2') !~ '^(0|[1-9][0-9]{0,11})(\.[0-9]{1,2})?$' THEN
                            v_rejection_code := 'FIELD_VALIDATION_FAILED';
                        ELSE
                            v_area := (v_payload ->> 'areaM2')::NUMERIC(14, 2);
                        END IF;
                    END IF;
                    IF v_rejection_code IS NULL AND v_payload ? 'location' THEN
                        IF jsonb_typeof(v_payload -> 'location') = 'null' THEN
                            v_location := NULL;
                        ELSIF jsonb_typeof(v_payload -> 'location') IS DISTINCT FROM 'string'
                           OR NOT public.farmly_is_coarse_grid(v_payload ->> 'location') THEN
                            v_rejection_code := 'FIELD_VALIDATION_FAILED';
                        ELSE
                            v_location := btrim(v_payload ->> 'location');
                        END IF;
                    END IF;
                END IF;
            END IF;
            IF v_rejection_code IS NULL THEN
                IF v_resource_id IS DISTINCT FROM p_farm_id THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSIF v_farm.version IS DISTINCT FROM v_base_version THEN
                    v_conflict_code := 'VERSION_CONFLICT';
                ELSIF v_farm.status <> 'active' THEN
                    v_rejection_code := 'RESOURCE_ARCHIVED';
                END IF;
            END IF;

        ELSIF v_type IN ('zone.create', 'zone.update', 'zone.archive') THEN
            IF jsonb_typeof(v_payload) IS DISTINCT FROM 'object'
               OR (v_payload - 'name' - 'type' - 'geometry' - 'areaM2') <> '{}'::JSONB THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF v_type = 'zone.archive' AND v_payload <> '{}'::JSONB THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF v_type = 'zone.create' AND NOT (
                v_payload ? 'name' AND v_payload ? 'type' AND v_payload ? 'geometry') THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF v_type = 'zone.update' AND v_payload = '{}'::JSONB THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            END IF;
            IF v_rejection_code IS NULL AND v_type <> 'zone.archive' THEN
                IF v_payload ? 'name' THEN
                    v_name := btrim(v_payload ->> 'name');
                    IF v_name IS NULL OR length(v_name) < 1 OR length(v_name) > 160 THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END IF;
                END IF;
                IF v_rejection_code IS NULL AND v_payload ? 'type'
                   AND (v_payload ->> 'type') NOT IN ('house', 'crop_plot', 'livestock_area', 'water', 'storage', 'other') THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                END IF;
                IF v_rejection_code IS NULL AND v_payload ? 'geometry' THEN
                    IF jsonb_typeof(v_payload -> 'geometry') IS DISTINCT FROM 'object'
                       OR ((v_payload -> 'geometry') - 'points') <> '{}'::JSONB
                       OR jsonb_typeof(v_payload -> 'geometry' -> 'points') IS DISTINCT FROM 'array'
                       OR jsonb_array_length(v_payload -> 'geometry' -> 'points') NOT BETWEEN 3 AND 128
                       OR EXISTS (
                           SELECT 1
                             FROM jsonb_array_elements(v_payload -> 'geometry' -> 'points') AS point
                            WHERE jsonb_typeof(point) IS DISTINCT FROM 'object'
                               OR (point - 'x' - 'y') <> '{}'::JSONB
                               OR jsonb_typeof(point -> 'x') IS DISTINCT FROM 'string'
                               OR jsonb_typeof(point -> 'y') IS DISTINCT FROM 'string'
                               OR (point ->> 'x') !~ '^(0(\.[0-9]+)?|1(\.0+)?)$'
                               OR (point ->> 'y') !~ '^(0(\.[0-9]+)?|1(\.0+)?)$'
                       ) THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END IF;
                END IF;
                IF v_rejection_code IS NULL AND v_payload ? 'areaM2' THEN
                    IF jsonb_typeof(v_payload -> 'areaM2') IS DISTINCT FROM 'string'
                       OR (v_payload ->> 'areaM2') !~ '^(0|[1-9][0-9]{0,11})(\.[0-9]{1,2})?$' THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    ELSE
                        v_area := (v_payload ->> 'areaM2')::NUMERIC(14, 2);
                    END IF;
                END IF;
            END IF;
            IF v_rejection_code IS NULL AND v_type <> 'zone.create' THEN
                SELECT * INTO v_row FROM public.zones AS zone
                 WHERE zone.organization_id = p_organization_id
                   AND zone.farm_id = p_farm_id AND zone.id = v_resource_id
                 FOR UPDATE;
                IF NOT FOUND THEN
                    v_rejection_code := 'RESOURCE_NOT_FOUND';
                ELSIF v_row.version IS DISTINCT FROM v_base_version THEN
                    v_conflict_code := 'VERSION_CONFLICT';
                ELSIF v_row.status = 'archived' THEN
                    v_rejection_code := 'RESOURCE_ARCHIVED';
                END IF;
            END IF;

        ELSIF v_type IN ('cropSpecies.create', 'cropSpecies.update', 'cropSpecies.archive') THEN
            IF jsonb_typeof(v_payload) IS DISTINCT FROM 'object'
               OR (v_payload - 'name' - 'harvestUnit') <> '{}'::JSONB THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF v_type = 'cropSpecies.archive' AND v_payload <> '{}'::JSONB THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF v_type = 'cropSpecies.create' AND NOT (v_payload ? 'name' AND v_payload ? 'harvestUnit') THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF v_type = 'cropSpecies.update' AND v_payload = '{}'::JSONB THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            END IF;
            IF v_rejection_code IS NULL AND v_type <> 'cropSpecies.archive' THEN
                IF v_payload ? 'name' THEN
                    v_name := btrim(v_payload ->> 'name');
                    IF v_name IS NULL OR length(v_name) < 1 OR length(v_name) > 160 THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END IF;
                END IF;
                IF v_rejection_code IS NULL AND v_payload ? 'harvestUnit'
                   AND (v_payload ->> 'harvestUnit') NOT IN ('kg', 'litre', 'pieces') THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                END IF;
            END IF;
            IF v_rejection_code IS NULL AND v_type <> 'cropSpecies.create' THEN
                SELECT * INTO v_row FROM public.crop_species AS species
                 WHERE species.organization_id = p_organization_id
                   AND species.farm_id = p_farm_id AND species.id = v_resource_id
                 FOR UPDATE;
                IF NOT FOUND THEN
                    v_rejection_code := 'RESOURCE_NOT_FOUND';
                ELSIF v_row.version IS DISTINCT FROM v_base_version THEN
                    v_conflict_code := 'VERSION_CONFLICT';
                ELSIF v_row.status = 'archived' THEN
                    v_rejection_code := 'RESOURCE_ARCHIVED';
                END IF;
            END IF;

        ELSIF v_type IN ('planting.create', 'planting.update', 'planting.archive') THEN
            IF jsonb_typeof(v_payload) IS DISTINCT FROM 'object'
               OR (v_payload - 'cropSpeciesId' - 'plotId' - 'status' - 'sowingDate' - 'expectedHarvestDate' - 'areaM2') <> '{}'::JSONB THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF v_type = 'planting.archive' AND v_payload <> '{}'::JSONB THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF v_type = 'planting.create' AND NOT (
                v_payload ? 'cropSpeciesId' AND v_payload ? 'plotId' AND v_payload ? 'sowingDate') THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF v_type = 'planting.update' AND v_payload = '{}'::JSONB THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            END IF;
            IF v_rejection_code IS NULL AND v_type <> 'planting.archive' THEN
                IF v_payload ? 'status'
                   AND (v_payload ->> 'status') NOT IN ('planned', 'active', 'harvested', 'completed', 'archived') THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                END IF;
                IF v_rejection_code IS NULL AND v_payload ? 'sowingDate' THEN
                    IF jsonb_typeof(v_payload -> 'sowingDate') IS DISTINCT FROM 'string'
                       OR (v_payload ->> 'sowingDate') !~ '^\d{4}-\d{2}-\d{2}$' THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    ELSE
                        BEGIN
                            v_date := (v_payload ->> 'sowingDate')::DATE;
                        EXCEPTION WHEN OTHERS THEN
                            v_rejection_code := 'FIELD_VALIDATION_FAILED';
                        END;
                    END IF;
                END IF;
                IF v_rejection_code IS NULL AND v_payload ? 'expectedHarvestDate' THEN
                    IF jsonb_typeof(v_payload -> 'expectedHarvestDate') IS DISTINCT FROM 'string'
                       OR (v_payload ->> 'expectedHarvestDate') !~ '^\d{4}-\d{2}-\d{2}$' THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    ELSE
                        BEGIN
                            v_date := (v_payload ->> 'expectedHarvestDate')::DATE;
                        EXCEPTION WHEN OTHERS THEN
                            v_rejection_code := 'FIELD_VALIDATION_FAILED';
                        END;
                    END IF;
                END IF;
                IF v_rejection_code IS NULL AND v_payload ? 'areaM2' THEN
                    IF jsonb_typeof(v_payload -> 'areaM2') IS DISTINCT FROM 'string'
                       OR (v_payload ->> 'areaM2') !~ '^(0|[1-9][0-9]{0,11})(\.[0-9]{1,2})?$' THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    ELSE
                        v_area := (v_payload ->> 'areaM2')::NUMERIC(14, 2);
                    END IF;
                END IF;
            END IF;
            IF v_rejection_code IS NULL AND v_type = 'planting.create' THEN
                IF (v_payload ->> 'cropSpeciesId') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
                   OR (v_payload ->> 'plotId') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSE
                -- Same-farm parents only (composite tenancy scope).
                SELECT * INTO v_row FROM public.crop_species AS species
                 WHERE species.organization_id = p_organization_id
                   AND species.farm_id = p_farm_id
                   AND species.id = (v_payload ->> 'cropSpeciesId')::UUID;
                IF NOT FOUND THEN
                    v_rejection_code := 'RESOURCE_NOT_FOUND';
                ELSIF v_row.status = 'archived' THEN
                    v_rejection_code := 'RESOURCE_ARCHIVED';
                ELSE
                    SELECT * INTO v_row FROM public.zones AS zone
                     WHERE zone.organization_id = p_organization_id
                       AND zone.farm_id = p_farm_id
                       AND zone.id = (v_payload ->> 'plotId')::UUID;
                    IF NOT FOUND THEN
                        v_rejection_code := 'RESOURCE_NOT_FOUND';
                    ELSIF v_row.status = 'archived' THEN
                        v_rejection_code := 'RESOURCE_ARCHIVED';
                    END IF;
                END IF;
                END IF;
            END IF;
            IF v_rejection_code IS NULL AND v_type <> 'planting.create' THEN
                SELECT * INTO v_row FROM public.plantings AS planting
                 WHERE planting.organization_id = p_organization_id
                   AND planting.farm_id = p_farm_id AND planting.id = v_resource_id
                 FOR UPDATE;
                IF NOT FOUND THEN
                    v_rejection_code := 'RESOURCE_NOT_FOUND';
                ELSIF v_row.version IS DISTINCT FROM v_base_version THEN
                    v_conflict_code := 'VERSION_CONFLICT';
                ELSIF v_row.status = 'archived' THEN
                    v_rejection_code := 'RESOURCE_ARCHIVED';
                END IF;
            END IF;

        ELSIF v_type IN ('herd.create', 'herd.update', 'herd.archive') THEN
            IF jsonb_typeof(v_payload) IS DISTINCT FROM 'object'
               OR (v_payload - 'mode' - 'status' - 'species') <> '{}'::JSONB THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF v_type = 'herd.archive' AND v_payload <> '{}' ::JSONB THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF v_type = 'herd.create' AND NOT (v_payload ? 'mode') THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF v_type = 'herd.update' AND v_payload = '{}'::JSONB THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            END IF;
            IF v_rejection_code IS NULL AND v_type <> 'herd.archive' THEN
                IF v_payload ? 'mode'
                   AND (v_payload ->> 'mode') NOT IN ('tracked', 'batch') THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                END IF;
                IF v_rejection_code IS NULL AND v_payload ? 'status'
                   AND (v_payload ->> 'status') NOT IN ('active', 'archived') THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                END IF;
                IF v_rejection_code IS NULL AND v_payload ? 'species' THEN
                    v_name := btrim(v_payload ->> 'species');
                    IF v_name IS NULL OR length(v_name) < 1 OR length(v_name) > 120 THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END IF;
                END IF;
            END IF;
            IF v_rejection_code IS NULL AND v_type <> 'herd.create' THEN
                SELECT * INTO v_row FROM public.herds AS herd
                 WHERE herd.organization_id = p_organization_id
                   AND herd.farm_id = p_farm_id AND herd.id = v_resource_id
                 FOR UPDATE;
                IF NOT FOUND THEN
                    v_rejection_code := 'RESOURCE_NOT_FOUND';
                ELSIF v_row.version IS DISTINCT FROM v_base_version THEN
                    v_conflict_code := 'VERSION_CONFLICT';
                ELSIF v_row.status = 'archived' THEN
                    v_rejection_code := 'RESOURCE_ARCHIVED';
                -- Herd mode is immutable once set (spec01 §5): a differing mode
                -- value is a field failure, not a CAS conflict.
                ELSIF v_type = 'herd.update' AND v_payload ? 'mode'
                      AND (v_payload ->> 'mode') IS DISTINCT FROM v_row.mode THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                END IF;
            END IF;

        ELSIF v_type IN ('animal.create', 'animal.update', 'animal.archive') THEN
            IF jsonb_typeof(v_payload) IS DISTINCT FROM 'object'
               OR (v_payload - 'herdId' - 'tag' - 'name' - 'birthDate' - 'status') <> '{}'::JSONB THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF v_type = 'animal.archive' AND v_payload <> '{}'::JSONB THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF v_type = 'animal.create' AND NOT (v_payload ? 'herdId' AND v_payload ? 'tag') THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF v_type = 'animal.update' AND v_payload = '{}'::JSONB THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            END IF;
            IF v_rejection_code IS NULL AND v_type <> 'animal.archive' THEN
                IF v_payload ? 'tag' THEN
                    v_name := btrim(v_payload ->> 'tag');
                    IF v_name IS NULL OR length(v_name) < 1 OR length(v_name) > 64 THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END IF;
                END IF;
                IF v_rejection_code IS NULL AND v_payload ? 'name' THEN
                    v_name := btrim(v_payload ->> 'name');
                    IF v_name IS NULL OR length(v_name) < 1 OR length(v_name) > 160 THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END IF;
                END IF;
                IF v_rejection_code IS NULL AND v_payload ? 'status'
                   AND (v_payload ->> 'status') NOT IN ('alive', 'sold', 'deceased') THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                END IF;
                IF v_rejection_code IS NULL AND v_payload ? 'birthDate' THEN
                    IF jsonb_typeof(v_payload -> 'birthDate') IS DISTINCT FROM 'string'
                       OR (v_payload ->> 'birthDate') !~ '^\d{4}-\d{2}-\d{2}$' THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    ELSE
                        BEGIN
                            v_date := (v_payload ->> 'birthDate')::DATE;
                        EXCEPTION WHEN OTHERS THEN
                            v_rejection_code := 'FIELD_VALIDATION_FAILED';
                        END;
                    END IF;
                END IF;
                IF v_rejection_code IS NULL AND v_type = 'animal.create' THEN
                    IF (v_payload ->> 'herdId') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    ELSE
                    -- Tracked herds take animal records; batch herds are counted
                    -- through livestock movements instead.
                    SELECT * INTO v_row FROM public.herds AS herd
                     WHERE herd.organization_id = p_organization_id
                       AND herd.farm_id = p_farm_id
                       AND herd.id = (v_payload ->> 'herdId')::UUID;
                    IF NOT FOUND THEN
                        v_rejection_code := 'RESOURCE_NOT_FOUND';
                    ELSIF v_row.status = 'archived' THEN
                        v_rejection_code := 'RESOURCE_ARCHIVED';
                    ELSIF v_row.mode <> 'tracked' THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END IF;
                    END IF;
                END IF;
            END IF;
            IF v_rejection_code IS NULL AND v_type <> 'animal.create' THEN
                SELECT * INTO v_row FROM public.animals AS animal
                 WHERE animal.organization_id = p_organization_id
                   AND animal.farm_id = p_farm_id AND animal.id = v_resource_id
                 FOR UPDATE;
                IF NOT FOUND THEN
                    v_rejection_code := 'RESOURCE_NOT_FOUND';
                ELSIF v_row.version IS DISTINCT FROM v_base_version THEN
                    v_conflict_code := 'VERSION_CONFLICT';
                ELSIF v_row.archived THEN
                    v_rejection_code := 'RESOURCE_ARCHIVED';
                END IF;
            END IF;

        ELSIF v_type IN ('waterTank.create', 'waterTank.update', 'waterTank.archive') THEN
            IF jsonb_typeof(v_payload) IS DISTINCT FROM 'object'
               OR (v_payload - 'name' - 'zoneId' - 'capacityLitres') <> '{}'::JSONB THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF v_type = 'waterTank.archive' AND v_payload <> '{}'::JSONB THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF v_type = 'waterTank.create' AND NOT (
                v_payload ? 'name' AND v_payload ? 'zoneId' AND v_payload ? 'capacityLitres') THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF v_type = 'waterTank.update' AND v_payload = '{}'::JSONB THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            END IF;
            IF v_rejection_code IS NULL AND v_type <> 'waterTank.archive' THEN
                IF v_payload ? 'name' THEN
                    v_name := btrim(v_payload ->> 'name');
                    IF v_name IS NULL OR length(v_name) < 1 OR length(v_name) > 160 THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END IF;
                END IF;
                IF v_rejection_code IS NULL AND v_payload ? 'capacityLitres' THEN
                    IF jsonb_typeof(v_payload -> 'capacityLitres') IS DISTINCT FROM 'string'
                       OR (v_payload ->> 'capacityLitres') !~ '^(0|[1-9][0-9]{0,15})(\.[0-9]{1,4})?$' THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    ELSE
                        v_capacity := (v_payload ->> 'capacityLitres')::NUMERIC(20, 4);
                    END IF;
                END IF;
                IF v_rejection_code IS NULL AND v_type = 'waterTank.create' THEN
                    IF (v_payload ->> 'zoneId') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    ELSE
                    SELECT * INTO v_row FROM public.zones AS zone
                     WHERE zone.organization_id = p_organization_id
                       AND zone.farm_id = p_farm_id
                       AND zone.id = (v_payload ->> 'zoneId')::UUID;
                    IF NOT FOUND THEN
                        v_rejection_code := 'RESOURCE_NOT_FOUND';
                    ELSIF v_row.status = 'archived' THEN
                        v_rejection_code := 'RESOURCE_ARCHIVED';
                    END IF;
                    END IF;
                END IF;
            END IF;
            IF v_rejection_code IS NULL AND v_type <> 'waterTank.create' THEN
                SELECT * INTO v_row FROM public.water_tanks AS tank
                 WHERE tank.organization_id = p_organization_id
                   AND tank.farm_id = p_farm_id AND tank.id = v_resource_id
                 FOR UPDATE;
                IF NOT FOUND THEN
                    v_rejection_code := 'RESOURCE_NOT_FOUND';
                ELSIF v_row.version IS DISTINCT FROM v_base_version THEN
                    v_conflict_code := 'VERSION_CONFLICT';
                ELSIF v_row.status = 'archived' THEN
                    v_rejection_code := 'RESOURCE_ARCHIVED';
                END IF;
            END IF;
        ELSIF v_type = 'plantingEvent.create' THEN
            IF jsonb_typeof(v_payload) IS DISTINCT FROM 'object'
               OR (v_payload - 'plantingId' - 'eventType' - 'note' - 'occurredOn') <> '{}'::JSONB
               OR NOT (v_payload ? 'plantingId' AND v_payload ? 'eventType') THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF (v_payload ->> 'plantingId') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSE
                v_name := btrim(v_payload ->> 'eventType');
                IF v_name IS NULL OR length(v_name) < 1 OR length(v_name) > 40 THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                END IF;
            END IF;
            IF v_rejection_code IS NULL AND v_payload ? 'occurredOn' THEN
                IF jsonb_typeof(v_payload -> 'occurredOn') IS DISTINCT FROM 'string'
                   OR (v_payload ->> 'occurredOn') !~ '^\d{4}-\d{2}-\d{2}$' THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSE
                    BEGIN
                        v_date := (v_payload ->> 'occurredOn')::DATE;
                    EXCEPTION WHEN OTHERS THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END;
                END IF;
            END IF;
            IF v_rejection_code IS NULL AND v_payload ? 'note' THEN
                IF jsonb_typeof(v_payload -> 'note') IS DISTINCT FROM 'string'
                   OR length(v_payload ->> 'note') > 500 THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                END IF;
            END IF;
            IF v_rejection_code IS NULL THEN
                SELECT * INTO v_row FROM public.plantings AS planting
                 WHERE planting.organization_id = p_organization_id
                   AND planting.farm_id = p_farm_id
                   AND planting.id = (v_payload ->> 'plantingId')::UUID
                 FOR UPDATE;
                IF NOT FOUND THEN
                    v_rejection_code := 'RESOURCE_NOT_FOUND';
                ELSIF v_row.status = 'archived' THEN
                    v_rejection_code := 'RESOURCE_ARCHIVED';
                END IF;
            END IF;

        ELSIF v_type = 'livestockMovement.create' THEN
            IF jsonb_typeof(v_payload) IS DISTINCT FROM 'object'
               OR (v_payload - 'herdId' - 'movementType' - 'delta' - 'occurredOn') <> '{}'::JSONB
               OR NOT (v_payload ? 'herdId' AND v_payload ? 'movementType' AND v_payload ? 'delta') THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF (v_payload ->> 'herdId') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSE
                v_name := btrim(v_payload ->> 'movementType');
                IF v_name IS NULL OR length(v_name) < 1 OR length(v_name) > 40 THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSIF jsonb_typeof(v_payload -> 'delta') IS DISTINCT FROM 'number'
                   OR (v_payload ->> 'delta') !~ '^-?[0-9]{1,9}$'
                   OR (v_payload ->> 'delta')::INTEGER = 0 THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                END IF;
            END IF;
            IF v_rejection_code IS NULL AND v_payload ? 'occurredOn' THEN
                IF jsonb_typeof(v_payload -> 'occurredOn') IS DISTINCT FROM 'string'
                   OR (v_payload ->> 'occurredOn') !~ '^\d{4}-\d{2}-\d{2}$' THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSE
                    BEGIN
                        v_date := (v_payload ->> 'occurredOn')::DATE;
                    EXCEPTION WHEN OTHERS THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END;
                END IF;
            END IF;
            IF v_rejection_code IS NULL THEN
                -- Batch herds only: tracked headcount derives from animal rows.
                SELECT * INTO v_row FROM public.herds AS herd
                 WHERE herd.organization_id = p_organization_id
                   AND herd.farm_id = p_farm_id
                   AND herd.id = (v_payload ->> 'herdId')::UUID
                 FOR UPDATE;
                IF NOT FOUND THEN
                    v_rejection_code := 'RESOURCE_NOT_FOUND';
                ELSIF v_row.status = 'archived' THEN
                    v_rejection_code := 'RESOURCE_ARCHIVED';
                ELSIF v_row.mode <> 'batch' THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSIF COALESCE((
                        SELECT sum(movement.delta)
                          FROM public.livestock_movements AS movement
                         WHERE movement.organization_id = p_organization_id
                           AND movement.farm_id = p_farm_id
                           AND movement.herd_id = v_row.id), 0)
                      + (v_payload ->> 'delta')::INTEGER < 0 THEN
                    -- A batch herd may never go negative (spec01 section 6).
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                END IF;
            END IF;

        ELSIF v_type IN ('animalObservation.create', 'productionRecord.create') THEN
            IF v_type = 'animalObservation.create' THEN
                IF jsonb_typeof(v_payload) IS DISTINCT FROM 'object'
                   OR (v_payload - 'herdId' - 'animalId' - 'note' - 'kind' - 'observedOn') <> '{}'::JSONB
                   OR NOT (v_payload ? 'note') THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSIF v_payload ? 'kind'
                      AND (v_payload ->> 'kind') NOT IN ('note', 'vet') THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                END IF;
                IF v_rejection_code IS NULL THEN
                    IF jsonb_typeof(v_payload -> 'note') IS DISTINCT FROM 'string'
                       OR length(btrim(v_payload ->> 'note')) < 1
                       OR length(v_payload ->> 'note') > 1000 THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END IF;
                END IF;
                IF v_rejection_code IS NULL AND v_payload ? 'observedOn' THEN
                    IF jsonb_typeof(v_payload -> 'observedOn') IS DISTINCT FROM 'string'
                       OR (v_payload ->> 'observedOn') !~ '^\d{4}-\d{2}-\d{2}$' THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    ELSE
                        BEGIN
                            v_date := (v_payload ->> 'observedOn')::DATE;
                        EXCEPTION WHEN OTHERS THEN
                            v_rejection_code := 'FIELD_VALIDATION_FAILED';
                        END;
                    END IF;
                END IF;
            ELSE
                IF jsonb_typeof(v_payload) IS DISTINCT FROM 'object'
                   OR (v_payload - 'herdId' - 'animalId' - 'product' - 'quantity' - 'recordedOn') <> '{}'::JSONB
                   OR NOT (v_payload ? 'product' AND v_payload ? 'quantity' AND v_payload ? 'recordedOn') THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSIF (v_payload ->> 'product') NOT IN ('milk', 'eggs', 'weight') THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSIF jsonb_typeof(v_payload -> 'quantity') IS DISTINCT FROM 'string'
                   OR (v_payload ->> 'quantity') !~ '^(0|[1-9][0-9]{0,15})(\.[0-9]{1,4})?$' THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSIF (v_payload ->> 'product') = 'eggs'
                      AND (v_payload ->> 'quantity') !~ '^[1-9][0-9]{0,15}$' THEN
                    -- pieces is an integer-only unit (spec04 section 5.2).
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSE
                    v_qty := (v_payload ->> 'quantity')::NUMERIC(20, 4);
                    IF v_qty <= 0 THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END IF;
                END IF;
                IF v_rejection_code IS NULL THEN
                    IF jsonb_typeof(v_payload -> 'recordedOn') IS DISTINCT FROM 'string'
                       OR (v_payload ->> 'recordedOn') !~ '^\d{4}-\d{2}-\d{2}$' THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    ELSE
                        BEGIN
                            v_date := (v_payload ->> 'recordedOn')::DATE;
                        EXCEPTION WHEN OTHERS THEN
                            v_rejection_code := 'FIELD_VALIDATION_FAILED';
                        END;
                    END IF;
                END IF;
            END IF;
            -- Exactly one subject, same-farm, non-archived; lock it.
            IF v_rejection_code IS NULL THEN
                IF (v_payload ? 'herdId') = (v_payload ? 'animalId') THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSIF v_payload ? 'animalId' THEN
                    IF (v_payload ->> 'animalId') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    ELSE
                        SELECT * INTO v_row FROM public.animals AS animal
                         WHERE animal.organization_id = p_organization_id
                           AND animal.farm_id = p_farm_id
                           AND animal.id = (v_payload ->> 'animalId')::UUID
                         FOR UPDATE;
                        IF NOT FOUND THEN
                            v_rejection_code := 'RESOURCE_NOT_FOUND';
                        ELSIF v_row.archived THEN
                            v_rejection_code := 'RESOURCE_ARCHIVED';
                        END IF;
                    END IF;
                ELSE
                    IF (v_payload ->> 'herdId') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    ELSE
                        SELECT * INTO v_row FROM public.herds AS herd
                         WHERE herd.organization_id = p_organization_id
                           AND herd.farm_id = p_farm_id
                           AND herd.id = (v_payload ->> 'herdId')::UUID
                         FOR UPDATE;
                        IF NOT FOUND THEN
                            v_rejection_code := 'RESOURCE_NOT_FOUND';
                        ELSIF v_row.status = 'archived' THEN
                            v_rejection_code := 'RESOURCE_ARCHIVED';
                        END IF;
                    END IF;
                END IF;
            END IF;

        ELSIF v_type IN ('taskTemplate.create', 'taskTemplate.update') THEN
            IF jsonb_typeof(v_payload) IS DISTINCT FROM 'object'
               OR (v_payload - 'title' - 'kind' - 'zoneId' - 'recurrence'
                   - 'startsOn' - 'endsOn' - 'assigneeMembershipId' - 'status') <> '{}'::JSONB THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF v_type = 'taskTemplate.create' AND NOT (v_payload ? 'title' AND v_payload ? 'recurrence') THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF v_type = 'taskTemplate.update' AND v_payload = '{}'::JSONB THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF v_type = 'taskTemplate.update' AND v_payload ? 'kind' THEN
                -- kind is immutable after create (spec04 section 5.2).
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            END IF;
            IF v_rejection_code IS NULL AND v_payload ? 'title' THEN
                v_name := btrim(v_payload ->> 'title');
                IF v_name IS NULL OR length(v_name) < 1 OR length(v_name) > 160 THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                END IF;
            END IF;
            IF v_rejection_code IS NULL AND v_payload ? 'kind'
               AND (v_payload ->> 'kind') NOT IN ('general', 'feeding', 'irrigation') THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            END IF;
            IF v_rejection_code IS NULL AND v_payload ? 'status' THEN
                IF (v_payload ->> 'status') NOT IN ('active', 'archived')
                   OR (v_type = 'taskTemplate.create' AND (v_payload ->> 'status') <> 'active') THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                END IF;
            END IF;
            IF v_rejection_code IS NULL AND v_payload ? 'recurrence' THEN
                IF jsonb_typeof(v_payload -> 'recurrence') IS DISTINCT FROM 'object'
                   OR ((v_payload -> 'recurrence') - 'freq' - 'timeOfDay' - 'daysOfWeek') <> '{}'::JSONB
                   OR NOT (v_payload -> 'recurrence' ? 'freq')
                   OR NOT (v_payload -> 'recurrence' ? 'timeOfDay')
                   OR (v_payload -> 'recurrence' ->> 'freq') NOT IN ('daily', 'weekly')
                   OR jsonb_typeof(v_payload -> 'recurrence' -> 'timeOfDay') IS DISTINCT FROM 'string'
                   OR (v_payload -> 'recurrence' ->> 'timeOfDay') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSIF (v_payload -> 'recurrence' ? 'daysOfWeek') THEN
                    IF (v_payload -> 'recurrence' ->> 'freq') <> 'weekly'
                       OR jsonb_typeof(v_payload -> 'recurrence' -> 'daysOfWeek') IS DISTINCT FROM 'array'
                       OR jsonb_array_length(v_payload -> 'recurrence' -> 'daysOfWeek') NOT BETWEEN 1 AND 7
                       OR EXISTS (
                           SELECT 1
                             FROM jsonb_array_elements(v_payload -> 'recurrence' -> 'daysOfWeek') AS day
                            WHERE jsonb_typeof(day) IS DISTINCT FROM 'number'
                               OR (day::TEXT) !~ '^[0-6]$'
                       ) THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END IF;
                END IF;
            END IF;
            IF v_rejection_code IS NULL AND v_payload ? 'startsOn' THEN
                IF jsonb_typeof(v_payload -> 'startsOn') IS DISTINCT FROM 'string'
                   OR (v_payload ->> 'startsOn') !~ '^\d{4}-\d{2}-\d{2}$' THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSE
                    BEGIN
                        v_date := (v_payload ->> 'startsOn')::DATE;
                    EXCEPTION WHEN OTHERS THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END;
                END IF;
            END IF;
            IF v_rejection_code IS NULL AND v_payload ? 'endsOn'
               AND jsonb_typeof(v_payload -> 'endsOn') IS DISTINCT FROM 'null' THEN
                IF jsonb_typeof(v_payload -> 'endsOn') IS DISTINCT FROM 'string'
                   OR (v_payload ->> 'endsOn') !~ '^\d{4}-\d{2}-\d{2}$' THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSE
                    BEGIN
                        v_date := (v_payload ->> 'endsOn')::DATE;
                    EXCEPTION WHEN OTHERS THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END;
                END IF;
            END IF;
            IF v_rejection_code IS NULL AND v_payload ? 'zoneId'
               AND jsonb_typeof(v_payload -> 'zoneId') IS DISTINCT FROM 'null' THEN
                IF (v_payload ->> 'zoneId') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSIF NOT EXISTS (
                    SELECT 1 FROM public.zones AS zone
                     WHERE zone.organization_id = p_organization_id
                       AND zone.farm_id = p_farm_id
                       AND zone.id = (v_payload ->> 'zoneId')::UUID
                       AND zone.status <> 'archived'
                ) THEN
                    v_rejection_code := 'RESOURCE_NOT_FOUND';
                END IF;
            END IF;
            IF v_rejection_code IS NULL AND v_payload ? 'assigneeMembershipId'
               AND jsonb_typeof(v_payload -> 'assigneeMembershipId') IS DISTINCT FROM 'null' THEN
                IF (v_payload ->> 'assigneeMembershipId') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSIF NOT EXISTS (
                    SELECT 1 FROM public.organization_memberships AS membership
                     WHERE membership.organization_id = p_organization_id
                       AND membership.id = (v_payload ->> 'assigneeMembershipId')::UUID
                       AND membership.status = 'active'
                ) THEN
                    v_rejection_code := 'RESOURCE_NOT_FOUND';
                END IF;
            END IF;
            IF v_rejection_code IS NULL AND v_type = 'taskTemplate.update' THEN
                SELECT * INTO v_row FROM public.task_templates AS template
                 WHERE template.organization_id = p_organization_id
                   AND template.farm_id = p_farm_id AND template.id = v_resource_id
                 FOR UPDATE;
                IF NOT FOUND THEN
                    v_rejection_code := 'RESOURCE_NOT_FOUND';
                ELSIF v_row.version IS DISTINCT FROM v_base_version THEN
                    v_conflict_code := 'VERSION_CONFLICT';
                ELSIF v_row.status = 'archived' THEN
                    v_rejection_code := 'RESOURCE_ARCHIVED';
                END IF;
            END IF;
        ELSIF v_type IN ('taskOccurrence.transition', 'irrigationTask.transition') THEN
            IF jsonb_typeof(v_payload) IS DISTINCT FROM 'object'
               OR (v_payload - 'templateId' - 'occurrenceDate' - 'slot' - 'transition' - 'reason') <> '{}'::JSONB
               OR NOT (v_payload ? 'templateId' AND v_payload ? 'occurrenceDate'
                       AND v_payload ? 'slot' AND v_payload ? 'transition') THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF (v_payload ->> 'templateId') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF (v_payload ->> 'transition') NOT IN ('complete', 'skip', 'reopen', 'cancel') THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            END IF;
            IF v_rejection_code IS NULL THEN
                IF jsonb_typeof(v_payload -> 'occurrenceDate') IS DISTINCT FROM 'string'
                   OR (v_payload ->> 'occurrenceDate') !~ '^\d{4}-\d{2}-\d{2}$' THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSE
                    BEGIN
                        v_occ_date := (v_payload ->> 'occurrenceDate')::DATE;
                    EXCEPTION WHEN OTHERS THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END;
                END IF;
            END IF;
            IF v_rejection_code IS NULL THEN
                IF jsonb_typeof(v_payload -> 'slot') IS DISTINCT FROM 'string' THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSE
                    v_slot := btrim(v_payload ->> 'slot');
                    IF length(v_slot) < 1 OR length(v_slot) > 40 THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END IF;
                END IF;
            END IF;
            IF v_rejection_code IS NULL AND v_payload ? 'reason' THEN
                IF jsonb_typeof(v_payload -> 'reason') IS DISTINCT FROM 'string'
                   OR length(v_payload ->> 'reason') > 500 THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                END IF;
            END IF;
            -- Deterministic occurrence id (spec04 section 5.2): the client
            -- computes resourceId from (farm, template, date, slot); the kernel
            -- recomputes and refuses any other id.
            IF v_rejection_code IS NULL THEN
                v_hash := md5('taskocc:' || p_farm_id::TEXT || ':'
                              || (v_payload ->> 'templateId') || ':'
                              || (v_payload ->> 'occurrenceDate') || ':' || v_slot);
                v_det_id := (substr(v_hash, 1, 8) || '-' || substr(v_hash, 9, 4)
                             || '-5' || substr(v_hash, 14, 3)
                             || '-8' || substr(v_hash, 18, 3)
                             || '-' || substr(v_hash, 21, 12))::UUID;
                IF v_det_id IS DISTINCT FROM v_resource_id THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                END IF;
            END IF;
            IF v_rejection_code IS NULL THEN
                SELECT * INTO v_row FROM public.task_templates AS template
                 WHERE template.organization_id = p_organization_id
                   AND template.farm_id = p_farm_id
                   AND template.id = (v_payload ->> 'templateId')::UUID
                 FOR UPDATE;
                IF NOT FOUND THEN
                    v_rejection_code := 'RESOURCE_NOT_FOUND';
                ELSIF v_row.status <> 'active' THEN
                    v_rejection_code := 'RESOURCE_ARCHIVED';
                ELSIF v_type = 'irrigationTask.transition' AND v_row.kind <> 'irrigation' THEN
                    -- The irrigation route only accepts irrigation templates;
                    -- there is still no actuator path (spec04 section 5.2).
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                END IF;
            END IF;
            IF v_rejection_code IS NULL THEN
                v_transition := v_payload ->> 'transition';
                -- reopen/cancel are manager-only; complete/skip is allowed for
                -- a worker only on an unassigned template or when the worker is
                -- the assignee (spec04 section 5.2).
                IF v_transition IN ('reopen', 'cancel') AND v_farm_write <> 'manager' THEN
                    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'FARMLY_PERMISSION_DENIED';
                END IF;
                IF v_transition IN ('complete', 'skip')
                   AND v_farm_write = 'worker'
                   AND v_row.assignee_membership_id IS NOT NULL
                   AND v_row.assignee_membership_id IS DISTINCT FROM v_membership_id THEN
                    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'FARMLY_PERMISSION_DENIED';
                END IF;
            END IF;
            -- The occurrence date must sit inside the template window. Nested
            -- IF: plpgsql evaluates record fields eagerly, so v_row access must
            -- not share the guard expression (v_row may be unassigned).
            IF v_rejection_code IS NULL THEN
                IF v_occ_date < v_row.starts_on
                   OR (v_row.ends_on IS NOT NULL AND v_occ_date > v_row.ends_on) THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                END IF;
            END IF;
            -- Materialize idempotently, then lock the row. An occurrence row is
            -- derived deterministic state; materializing it is not a fact write.
            IF v_rejection_code IS NULL THEN
                -- RETURNING distinguishes "materialized now" from "already
                -- existed": only the latter may carry a CAS baseVersion.
                v_record_id := NULL;
                INSERT INTO public.task_occurrences (
                    organization_id, farm_id, id, template_id, occurrence_date, slot,
                    status, due_at, created_at, updated_at
                ) VALUES (
                    p_organization_id, p_farm_id, v_det_id,
                    (v_payload ->> 'templateId')::UUID, v_occ_date, v_slot, 'open',
                    ((v_occ_date + (v_row.recurrence ->> 'timeOfDay')::TIME)::TIMESTAMP
                        AT TIME ZONE v_farm.timezone),
                    clock_timestamp(), clock_timestamp()
                )
                ON CONFLICT ON CONSTRAINT task_occurrences_unique_slot DO NOTHING
                RETURNING id INTO v_record_id;
                IF v_record_id IS NOT NULL AND v_base_version IS NOT NULL THEN
                    -- Freshly materialized: claiming a version is a CAS lie.
                    v_conflict_code := 'VERSION_CONFLICT';
                END IF;
                SELECT * INTO v_occ FROM public.task_occurrences AS occurrence
                 WHERE occurrence.organization_id = p_organization_id
                   AND occurrence.farm_id = p_farm_id
                   AND occurrence.id = v_det_id
                 FOR UPDATE;
                IF v_record_id IS NULL
                   AND v_occ.version IS DISTINCT FROM v_base_version THEN
                    v_conflict_code := 'VERSION_CONFLICT';
                END IF;
                -- State machine: complete/skip from open; reopen from any
                -- terminal; cancel from non-terminal.
                v_from_status := v_occ.status;
                IF v_conflict_code IS NULL THEN
                    IF v_transition = 'complete' AND v_occ.status = 'open' THEN
                        v_to_status := 'done';
                    ELSIF v_transition = 'skip' AND v_occ.status = 'open' THEN
                        v_to_status := 'skipped';
                    ELSIF v_transition = 'reopen' AND v_occ.status IN ('done', 'skipped', 'cancelled') THEN
                        v_to_status := 'open';
                    ELSIF v_transition = 'cancel' AND v_occ.status IN ('open', 'done', 'skipped') THEN
                        v_to_status := 'cancelled';
                    ELSE
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END IF;
                END IF;
            END IF;

        ELSIF v_type IN ('harvest.create', 'harvest.correction.propose',
                         'harvest.correction.apply', 'harvest.void') THEN
            IF v_type = 'harvest.create' THEN
                IF jsonb_typeof(v_payload) IS DISTINCT FROM 'object'
                   OR (v_payload - 'plantingId' - 'quantityKg' - 'harvestDate') <> '{}'::JSONB
                   OR NOT (v_payload ? 'plantingId' AND v_payload ? 'quantityKg' AND v_payload ? 'harvestDate') THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSIF (v_payload ->> 'plantingId') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSIF jsonb_typeof(v_payload -> 'quantityKg') IS DISTINCT FROM 'string'
                   OR (v_payload ->> 'quantityKg') !~ '^(0|[1-9][0-9]{0,15})(\.[0-9]{1,4})?$' THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSE
                    v_qty := (v_payload ->> 'quantityKg')::NUMERIC(20, 4);
                    IF v_qty <= 0 THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END IF;
                END IF;
                IF v_rejection_code IS NULL THEN
                    IF jsonb_typeof(v_payload -> 'harvestDate') IS DISTINCT FROM 'string'
                       OR (v_payload ->> 'harvestDate') !~ '^\d{4}-\d{2}-\d{2}$' THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    ELSE
                        BEGIN
                            v_date := (v_payload ->> 'harvestDate')::DATE;
                        EXCEPTION WHEN OTHERS THEN
                            v_rejection_code := 'FIELD_VALIDATION_FAILED';
                        END;
                    END IF;
                END IF;
                IF v_rejection_code IS NULL THEN
                    SELECT * INTO v_row FROM public.plantings AS planting
                     WHERE planting.organization_id = p_organization_id
                       AND planting.farm_id = p_farm_id
                       AND planting.id = (v_payload ->> 'plantingId')::UUID
                     FOR UPDATE;
                    IF NOT FOUND THEN
                        v_rejection_code := 'RESOURCE_NOT_FOUND';
                    ELSIF v_row.status = 'archived' THEN
                        v_rejection_code := 'RESOURCE_ARCHIVED';
                    END IF;
                END IF;
            ELSE
                -- propose / apply / void all target an existing harvest head.
                IF v_type = 'harvest.correction.propose' THEN
                    IF jsonb_typeof(v_payload) IS DISTINCT FROM 'object'
                       OR (v_payload - 'proposedQuantityKg' - 'reason') <> '{}'::JSONB
                       OR NOT (v_payload ? 'proposedQuantityKg' AND v_payload ? 'reason') THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END IF;
                ELSIF v_type = 'harvest.correction.apply' THEN
                    IF jsonb_typeof(v_payload) IS DISTINCT FROM 'object'
                       OR (v_payload - 'proposedQuantityKg' - 'reason' - 'proposalId') <> '{}'::JSONB
                       OR NOT (v_payload ? 'proposedQuantityKg') THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    ELSIF v_payload ? 'proposalId'
                          AND (v_payload ->> 'proposalId') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END IF;
                ELSE
                    IF jsonb_typeof(v_payload) IS DISTINCT FROM 'object'
                       OR (v_payload - 'reason') <> '{}'::JSONB
                       OR NOT (v_payload ? 'reason') THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END IF;
                END IF;
                IF v_rejection_code IS NULL AND v_payload ? 'proposedQuantityKg' THEN
                    IF jsonb_typeof(v_payload -> 'proposedQuantityKg') IS DISTINCT FROM 'string'
                       OR (v_payload ->> 'proposedQuantityKg') !~ '^(0|[1-9][0-9]{0,15})(\.[0-9]{1,4})?$' THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    ELSE
                        v_qty := (v_payload ->> 'proposedQuantityKg')::NUMERIC(20, 4);
                        IF v_qty <= 0 THEN
                            v_rejection_code := 'FIELD_VALIDATION_FAILED';
                        END IF;
                    END IF;
                END IF;
                IF v_rejection_code IS NULL AND v_payload ? 'reason' THEN
                    IF jsonb_typeof(v_payload -> 'reason') IS DISTINCT FROM 'string'
                       OR length(btrim(v_payload ->> 'reason')) < 1
                       OR length(v_payload ->> 'reason') > 500 THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END IF;
                END IF;
                IF v_rejection_code IS NULL THEN
                    SELECT * INTO v_head FROM public.harvest_heads AS head
                     WHERE head.organization_id = p_organization_id
                       AND head.farm_id = p_farm_id
                       AND head.harvest_id = v_resource_id
                     FOR UPDATE;
                    IF NOT FOUND THEN
                        v_rejection_code := 'RESOURCE_NOT_FOUND';
                    ELSIF v_type = 'harvest.correction.propose' THEN
                        IF v_head.status <> 'active' THEN
                            v_rejection_code := 'FIELD_VALIDATION_FAILED';
                        END IF;
                    ELSE
                        IF v_head.version IS DISTINCT FROM v_base_version THEN
                            v_conflict_code := 'VERSION_CONFLICT';
                        ELSIF v_head.status <> 'active' THEN
                            v_rejection_code := 'FIELD_VALIDATION_FAILED';
                        END IF;
                    END IF;
                END IF;
                IF v_rejection_code IS NULL AND v_conflict_code IS NULL
                   AND v_type = 'harvest.correction.apply' AND v_payload ? 'proposalId' THEN
                    SELECT * INTO v_proposal FROM public.correction_proposals AS proposal
                     WHERE proposal.organization_id = p_organization_id
                       AND proposal.farm_id = p_farm_id
                       AND proposal.id = (v_payload ->> 'proposalId')::UUID
                     FOR UPDATE;
                    IF NOT FOUND
                       OR v_proposal.harvest_id <> v_resource_id
                       OR v_proposal.status <> 'pending' THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END IF;
                END IF;
            END IF;

        ELSIF v_type = 'moistureReading.create' THEN
            IF jsonb_typeof(v_payload) IS DISTINCT FROM 'object'
               OR (v_payload - 'zoneId' - 'value' - 'method' - 'measuredAt') <> '{}'::JSONB
               OR NOT (v_payload ? 'zoneId' AND v_payload ? 'value'
                       AND v_payload ? 'method' AND v_payload ? 'measuredAt') THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF (v_payload ->> 'zoneId') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF (v_payload ->> 'method') NOT IN ('relative_percent', 'vwc_percent') THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF jsonb_typeof(v_payload -> 'value') IS DISTINCT FROM 'string'
               OR (v_payload ->> 'value') !~ '^(0|[1-9][0-9]{0,2})(\.[0-9]{1,2})?$' THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF (v_payload ->> 'value')::NUMERIC(5, 2) > 100 THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            END IF;
            IF v_rejection_code IS NULL THEN
                IF jsonb_typeof(v_payload -> 'measuredAt') IS DISTINCT FROM 'string' THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSE
                    BEGIN
                        v_measured := (v_payload ->> 'measuredAt')::TIMESTAMPTZ;
                    EXCEPTION WHEN OTHERS THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END;
                    -- Clock-skew policy: manual readings may not be dated more
                    -- than 24h in the future (spec04 section 5.2).
                    IF v_rejection_code IS NULL
                       AND (v_measured > clock_timestamp() + INTERVAL '1 day'
                            OR v_measured < TIMESTAMPTZ '2000-01-01') THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END IF;
                END IF;
            END IF;
            IF v_rejection_code IS NULL THEN
                SELECT * INTO v_row FROM public.zones AS zone
                 WHERE zone.organization_id = p_organization_id
                   AND zone.farm_id = p_farm_id
                   AND zone.id = (v_payload ->> 'zoneId')::UUID
                 FOR UPDATE;
                IF NOT FOUND THEN
                    v_rejection_code := 'RESOURCE_NOT_FOUND';
                ELSIF v_row.status = 'archived' THEN
                    v_rejection_code := 'RESOURCE_ARCHIVED';
                END IF;
            END IF;

        ELSIF v_type IN ('waterReading.create', 'waterUsage.create') THEN
            IF v_type = 'waterReading.create' THEN
                IF jsonb_typeof(v_payload) IS DISTINCT FROM 'object'
                   OR (v_payload - 'tankId' - 'storedLitres' - 'source' - 'measuredAt') <> '{}'::JSONB
                   OR NOT (v_payload ? 'tankId' AND v_payload ? 'storedLitres' AND v_payload ? 'source') THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSIF jsonb_typeof(v_payload -> 'storedLitres') IS DISTINCT FROM 'string'
                   OR (v_payload ->> 'storedLitres') !~ '^(0|[1-9][0-9]{0,15})(\.[0-9]{1,4})?$' THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSIF jsonb_typeof(v_payload -> 'source') IS DISTINCT FROM 'string'
                   OR length(btrim(v_payload ->> 'source')) < 1
                   OR length(v_payload ->> 'source') > 40 THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                END IF;
                IF v_rejection_code IS NULL AND v_payload ? 'measuredAt' THEN
                    IF jsonb_typeof(v_payload -> 'measuredAt') IS DISTINCT FROM 'string' THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    ELSE
                        BEGIN
                            v_measured := (v_payload ->> 'measuredAt')::TIMESTAMPTZ;
                        EXCEPTION WHEN OTHERS THEN
                            v_rejection_code := 'FIELD_VALIDATION_FAILED';
                        END;
                        IF v_rejection_code IS NULL
                           AND v_measured > clock_timestamp() + INTERVAL '1 day' THEN
                            v_rejection_code := 'FIELD_VALIDATION_FAILED';
                        END IF;
                    END IF;
                END IF;
            ELSE
                IF jsonb_typeof(v_payload) IS DISTINCT FROM 'object'
                   OR (v_payload - 'tankId' - 'usageLitres' - 'usageDate' - 'note') <> '{}'::JSONB
                   OR NOT (v_payload ? 'tankId' AND v_payload ? 'usageLitres' AND v_payload ? 'usageDate') THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSIF jsonb_typeof(v_payload -> 'usageLitres') IS DISTINCT FROM 'string'
                   OR (v_payload ->> 'usageLitres') !~ '^(0|[1-9][0-9]{0,15})(\.[0-9]{1,4})?$' THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSE
                    v_qty := (v_payload ->> 'usageLitres')::NUMERIC(20, 4);
                    IF v_qty <= 0 THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END IF;
                END IF;
                IF v_rejection_code IS NULL THEN
                    IF jsonb_typeof(v_payload -> 'usageDate') IS DISTINCT FROM 'string'
                       OR (v_payload ->> 'usageDate') !~ '^\d{4}-\d{2}-\d{2}$' THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    ELSE
                        BEGIN
                            v_date := (v_payload ->> 'usageDate')::DATE;
                        EXCEPTION WHEN OTHERS THEN
                            v_rejection_code := 'FIELD_VALIDATION_FAILED';
                        END;
                    END IF;
                END IF;
                IF v_rejection_code IS NULL AND v_payload ? 'note' THEN
                    IF jsonb_typeof(v_payload -> 'note') IS DISTINCT FROM 'string'
                       OR length(v_payload ->> 'note') > 200 THEN
                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                    END IF;
                END IF;
            END IF;
            IF v_rejection_code IS NULL THEN
                IF (v_payload ->> 'tankId') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
                    v_rejection_code := 'FIELD_VALIDATION_FAILED';
                ELSE
                    SELECT * INTO v_row FROM public.water_tanks AS tank
                     WHERE tank.organization_id = p_organization_id
                       AND tank.farm_id = p_farm_id
                       AND tank.id = (v_payload ->> 'tankId')::UUID
                     FOR UPDATE;
                    IF NOT FOUND THEN
                        v_rejection_code := 'RESOURCE_NOT_FOUND';
                    ELSIF v_row.status = 'archived' THEN
                        v_rejection_code := 'RESOURCE_ARCHIVED';
                    END IF;
                END IF;
            END IF;
        END IF;
    END IF;

    IF v_rejection_code IS NULL AND jsonb_typeof(p_intent -> 'dependsOn') IS DISTINCT FROM 'array' THEN
        v_rejection_code := 'FIELD_VALIDATION_FAILED';
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

    IF v_conflict_code IS NOT NULL THEN
        RETURN QUERY SELECT 'conflict'::TEXT, v_conflict_code,
            jsonb_build_object('operationId', p_operation_id, 'outcome', 'conflict', 'code', v_conflict_code),
            v_scope_policy_version, v_current_epoch, FALSE;
        RETURN;
    END IF;

    IF v_rejection_code IS NOT NULL THEN
        v_created_at := clock_timestamp();
        v_result_data := jsonb_build_object('operationId', p_operation_id, 'outcome', 'rejected', 'code', v_rejection_code);
        INSERT INTO public.applied_operations (
            organization_id, actor_pseudonym, operation_id, request_hash, continuity_epoch,
            outcome, result_code, resource_id, farm_id, created_at, completed_at
        ) VALUES (
            p_organization_id, p_actor_pseudonym, p_operation_id, p_request_hash, v_current_epoch,
            'rejected', v_rejection_code, NULL, p_farm_id, v_created_at, v_created_at
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
        outcome, resource_id, farm_id, result_version, created_at
    ) VALUES (
        p_organization_id, p_actor_pseudonym, p_operation_id, p_request_hash, v_current_epoch,
        'pending', v_resource_id, COALESCE(p_farm_id, v_resource_id), 1, v_created_at
    );

    IF v_type = 'farm.create' THEN
        INSERT INTO public.farms (
            id, organization_id, name, area_m2, timezone, location, status, version, created_at, updated_at
        ) VALUES (
            v_resource_id, p_organization_id, v_name, v_area, v_timezone, v_location, 'active', 1, v_created_at, v_created_at
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

        v_view := jsonb_build_object(
            'farmId', v_resource_id,
            'name', v_name,
            'areaM2', CASE WHEN v_area IS NULL THEN NULL ELSE v_area::TEXT END,
            'timezone', v_timezone,
            'location', v_location,
            'status', 'active',
            'version', 1
        );
        v_view_key := 'farm';
    ELSE
        -- Every applied farm-scoped mutation advances the farm clock by one
        -- revision and emits one change set + one audit event.
        UPDATE public.farm_clocks AS clock
           SET revision = clock.revision + 1,
               updated_at = v_created_at
         WHERE clock.organization_id = p_organization_id
           AND clock.farm_id = p_farm_id
         RETURNING clock.revision INTO v_revision;
        IF v_revision IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = '23502', MESSAGE = 'farm clock missing';
        END IF;

        IF v_type = 'farm.update' THEN
            UPDATE public.farms AS farm
               SET name = COALESCE(v_name, farm.name),
                   timezone = COALESCE(v_timezone, farm.timezone),
                   area_m2 = CASE WHEN v_payload ? 'areaM2' THEN v_area ELSE farm.area_m2 END,
                   location = CASE WHEN v_payload ? 'location' THEN v_location ELSE farm.location END,
                   version = farm.version + 1,
                   updated_at = v_created_at
             WHERE farm.organization_id = p_organization_id
               AND farm.id = p_farm_id
             RETURNING farm.* INTO v_farm;
        ELSIF v_type = 'farm.archive' THEN
            UPDATE public.farms AS farm
               SET status = 'archived',
                   version = farm.version + 1,
                   updated_at = v_created_at
             WHERE farm.organization_id = p_organization_id
               AND farm.id = p_farm_id
             RETURNING farm.* INTO v_farm;
            -- Directory-visible transition: bump the org scope policy version.
            UPDATE public.organizations
               SET policy_version = policy_version + 1,
                   updated_at = v_created_at
             WHERE id = p_organization_id
             RETURNING policy_version INTO v_scope_policy_version;
        ELSIF v_type LIKE 'zone.%' THEN
            IF v_type = 'zone.create' THEN
                INSERT INTO public.zones (
                    organization_id, farm_id, id, name, type, geometry, area_m2,
                    status, version, created_at, updated_at
                ) VALUES (
                    p_organization_id, p_farm_id, v_resource_id, v_name, v_payload ->> 'type',
                    v_payload -> 'geometry', v_area, 'active', 1, v_created_at, v_created_at
                );
            ELSE
                UPDATE public.zones AS zone
                   SET name = CASE WHEN v_payload ? 'name' THEN v_name ELSE zone.name END,
                       type = CASE WHEN v_payload ? 'type' THEN v_payload ->> 'type' ELSE zone.type END,
                       geometry = CASE WHEN v_payload ? 'geometry' THEN v_payload -> 'geometry' ELSE zone.geometry END,
                       area_m2 = CASE WHEN v_payload ? 'areaM2' THEN v_area ELSE zone.area_m2 END,
                       status = CASE WHEN v_type = 'zone.archive' THEN 'archived' ELSE zone.status END,
                       version = zone.version + 1,
                       updated_at = v_created_at
                 WHERE zone.organization_id = p_organization_id
                   AND zone.farm_id = p_farm_id
                   AND zone.id = v_resource_id
                 RETURNING zone.* INTO v_row;
            END IF;
        ELSIF v_type LIKE 'cropSpecies.%' THEN
            IF v_type = 'cropSpecies.create' THEN
                INSERT INTO public.crop_species (
                    organization_id, farm_id, id, name, harvest_unit,
                    status, version, created_at, updated_at
                ) VALUES (
                    p_organization_id, p_farm_id, v_resource_id, v_name, v_payload ->> 'harvestUnit',
                    'active', 1, v_created_at, v_created_at
                );
            ELSE
                UPDATE public.crop_species AS species
                   SET name = CASE WHEN v_payload ? 'name' THEN v_name ELSE species.name END,
                       harvest_unit = CASE WHEN v_payload ? 'harvestUnit' THEN v_payload ->> 'harvestUnit' ELSE species.harvest_unit END,
                       status = CASE WHEN v_type = 'cropSpecies.archive' THEN 'archived' ELSE species.status END,
                       version = species.version + 1,
                       updated_at = v_created_at
                 WHERE species.organization_id = p_organization_id
                   AND species.farm_id = p_farm_id
                   AND species.id = v_resource_id
                 RETURNING species.* INTO v_row;
            END IF;
        ELSIF v_type LIKE 'planting.%' THEN
            IF v_type = 'planting.create' THEN
                INSERT INTO public.plantings (
                    organization_id, farm_id, id, crop_species_id, plot_id,
                    sowing_date, expected_harvest_date, area_m2, status, version,
                    created_at, updated_at
                ) VALUES (
                    p_organization_id, p_farm_id, v_resource_id,
                    (v_payload ->> 'cropSpeciesId')::UUID, (v_payload ->> 'plotId')::UUID,
                    (v_payload ->> 'sowingDate')::DATE,
                    CASE WHEN v_payload ? 'expectedHarvestDate' THEN (v_payload ->> 'expectedHarvestDate')::DATE ELSE NULL END,
                    v_area,
                    COALESCE(v_payload ->> 'status', 'planned'), 1, v_created_at, v_created_at
                );
            ELSE
                UPDATE public.plantings AS planting
                   SET status = CASE
                           WHEN v_type = 'planting.archive' THEN 'archived'
                           WHEN v_payload ? 'status' THEN v_payload ->> 'status'
                           ELSE planting.status END,
                       sowing_date = CASE WHEN v_payload ? 'sowingDate' THEN (v_payload ->> 'sowingDate')::DATE ELSE planting.sowing_date END,
                       expected_harvest_date = CASE WHEN v_payload ? 'expectedHarvestDate' THEN (v_payload ->> 'expectedHarvestDate')::DATE ELSE planting.expected_harvest_date END,
                       area_m2 = CASE WHEN v_payload ? 'areaM2' THEN v_area ELSE planting.area_m2 END,
                       version = planting.version + 1,
                       updated_at = v_created_at
                 WHERE planting.organization_id = p_organization_id
                   AND planting.farm_id = p_farm_id
                   AND planting.id = v_resource_id
                 RETURNING planting.* INTO v_row;
            END IF;
        ELSIF v_type LIKE 'herd.%' THEN
            IF v_type = 'herd.create' THEN
                INSERT INTO public.herds (
                    organization_id, farm_id, id, mode, species,
                    status, version, created_at, updated_at
                ) VALUES (
                    p_organization_id, p_farm_id, v_resource_id, v_payload ->> 'mode', v_name,
                    COALESCE(v_payload ->> 'status', 'active'), 1, v_created_at, v_created_at
                );
            ELSE
                UPDATE public.herds AS herd
                   SET species = CASE WHEN v_payload ? 'species' THEN v_name ELSE herd.species END,
                       status = CASE
                           WHEN v_type = 'herd.archive' THEN 'archived'
                           WHEN v_payload ? 'status' THEN v_payload ->> 'status'
                           ELSE herd.status END,
                       version = herd.version + 1,
                       updated_at = v_created_at
                 WHERE herd.organization_id = p_organization_id
                   AND herd.farm_id = p_farm_id
                   AND herd.id = v_resource_id
                 RETURNING herd.* INTO v_row;
            END IF;
        ELSIF v_type LIKE 'animal.%' THEN
            IF v_type = 'animal.create' THEN
                INSERT INTO public.animals (
                    organization_id, farm_id, id, herd_id, tag, name, birth_date,
                    status, archived, version, created_at, updated_at
                ) VALUES (
                    p_organization_id, p_farm_id, v_resource_id, (v_payload ->> 'herdId')::UUID,
                    btrim(v_payload ->> 'tag'),
                    CASE WHEN v_payload ? 'name' THEN btrim(v_payload ->> 'name') ELSE NULL END,
                    CASE WHEN v_payload ? 'birthDate' THEN (v_payload ->> 'birthDate')::DATE ELSE NULL END,
                    COALESCE(v_payload ->> 'status', 'alive'), FALSE, 1, v_created_at, v_created_at
                );
            ELSE
                UPDATE public.animals AS animal
                   SET tag = CASE WHEN v_payload ? 'tag' THEN btrim(v_payload ->> 'tag') ELSE animal.tag END,
                       name = CASE WHEN v_payload ? 'name' THEN btrim(v_payload ->> 'name') ELSE animal.name END,
                       birth_date = CASE WHEN v_payload ? 'birthDate' THEN (v_payload ->> 'birthDate')::DATE ELSE animal.birth_date END,
                       status = CASE WHEN v_payload ? 'status' THEN v_payload ->> 'status' ELSE animal.status END,
                       archived = CASE WHEN v_type = 'animal.archive' THEN TRUE ELSE animal.archived END,
                       version = animal.version + 1,
                       updated_at = v_created_at
                 WHERE animal.organization_id = p_organization_id
                   AND animal.farm_id = p_farm_id
                   AND animal.id = v_resource_id
                 RETURNING animal.* INTO v_row;
            END IF;
        ELSIF v_type LIKE 'waterTank.%' THEN
            IF v_type = 'waterTank.create' THEN
                INSERT INTO public.water_tanks (
                    organization_id, farm_id, id, name, zone_id, capacity_litres,
                    status, version, created_at, updated_at
                ) VALUES (
                    p_organization_id, p_farm_id, v_resource_id, v_name,
                    (v_payload ->> 'zoneId')::UUID, v_capacity,
                    'active', 1, v_created_at, v_created_at
                );
            ELSE
                UPDATE public.water_tanks AS tank
                   SET name = CASE WHEN v_payload ? 'name' THEN v_name ELSE tank.name END,
                       capacity_litres = CASE WHEN v_payload ? 'capacityLitres' THEN v_capacity ELSE tank.capacity_litres END,
                       status = CASE WHEN v_type = 'waterTank.archive' THEN 'archived' ELSE tank.status END,
                       version = tank.version + 1,
                       updated_at = v_created_at
                 WHERE tank.organization_id = p_organization_id
                   AND tank.farm_id = p_farm_id
                   AND tank.id = v_resource_id
                 RETURNING tank.* INTO v_row;
            END IF;
        ELSIF v_type = 'plantingEvent.create' THEN
            INSERT INTO public.planting_events (
                organization_id, farm_id, id, planting_id, event_type, note,
                occurred_on, operation_id, created_at
            ) VALUES (
                p_organization_id, p_farm_id, v_resource_id,
                (v_payload ->> 'plantingId')::UUID,
                btrim(v_payload ->> 'eventType'),
                CASE WHEN v_payload ? 'note' THEN v_payload ->> 'note' ELSE NULL END,
                CASE WHEN v_payload ? 'occurredOn' THEN (v_payload ->> 'occurredOn')::DATE ELSE NULL END,
                p_operation_id, v_created_at
            ) RETURNING * INTO v_row;

        ELSIF v_type = 'livestockMovement.create' THEN
            INSERT INTO public.livestock_movements (
                organization_id, farm_id, id, herd_id, movement_type, delta,
                occurred_at, operation_id, created_at
            ) VALUES (
                p_organization_id, p_farm_id, v_resource_id,
                (v_payload ->> 'herdId')::UUID,
                btrim(v_payload ->> 'movementType'),
                (v_payload ->> 'delta')::INTEGER,
                CASE WHEN v_payload ? 'occurredOn'
                     THEN ((v_payload ->> 'occurredOn')::DATE)::TIMESTAMP AT TIME ZONE v_farm.timezone
                     ELSE v_created_at END,
                p_operation_id, v_created_at
            ) RETURNING * INTO v_row;

        ELSIF v_type = 'animalObservation.create' THEN
            INSERT INTO public.animal_observations (
                organization_id, farm_id, id, herd_id, animal_id, kind, note,
                observed_on, operation_id, created_at
            ) VALUES (
                p_organization_id, p_farm_id, v_resource_id,
                CASE WHEN v_payload ? 'herdId' THEN (v_payload ->> 'herdId')::UUID ELSE NULL END,
                CASE WHEN v_payload ? 'animalId' THEN (v_payload ->> 'animalId')::UUID ELSE NULL END,
                COALESCE(v_payload ->> 'kind', 'note'),
                btrim(v_payload ->> 'note'),
                CASE WHEN v_payload ? 'observedOn' THEN (v_payload ->> 'observedOn')::DATE ELSE NULL END,
                p_operation_id, v_created_at
            ) RETURNING * INTO v_row;

        ELSIF v_type = 'productionRecord.create' THEN
            INSERT INTO public.production_records (
                organization_id, farm_id, id, herd_id, animal_id, product,
                quantity, unit, recorded_on, operation_id, created_at
            ) VALUES (
                p_organization_id, p_farm_id, v_resource_id,
                CASE WHEN v_payload ? 'herdId' THEN (v_payload ->> 'herdId')::UUID ELSE NULL END,
                CASE WHEN v_payload ? 'animalId' THEN (v_payload ->> 'animalId')::UUID ELSE NULL END,
                v_payload ->> 'product',
                (v_payload ->> 'quantity')::NUMERIC(20, 4),
                CASE v_payload ->> 'product'
                    WHEN 'milk' THEN 'litre' WHEN 'eggs' THEN 'pieces' ELSE 'kg' END,
                (v_payload ->> 'recordedOn')::DATE,
                p_operation_id, v_created_at
            ) RETURNING * INTO v_row;

        ELSIF v_type = 'taskTemplate.create' THEN
            INSERT INTO public.task_templates (
                organization_id, farm_id, id, title, kind, zone_id, recurrence,
                assignee_membership_id, starts_on, ends_on, status, version,
                created_at, updated_at
            ) VALUES (
                p_organization_id, p_farm_id, v_resource_id,
                btrim(v_payload ->> 'title'),
                COALESCE(v_payload ->> 'kind', 'general'),
                CASE WHEN v_payload ? 'zoneId'
                          AND jsonb_typeof(v_payload -> 'zoneId') IS DISTINCT FROM 'null'
                     THEN (v_payload ->> 'zoneId')::UUID ELSE NULL END,
                v_payload -> 'recurrence',
                CASE WHEN v_payload ? 'assigneeMembershipId'
                          AND jsonb_typeof(v_payload -> 'assigneeMembershipId') IS DISTINCT FROM 'null'
                     THEN (v_payload ->> 'assigneeMembershipId')::UUID ELSE NULL END,
                CASE WHEN v_payload ? 'startsOn'
                     THEN (v_payload ->> 'startsOn')::DATE
                     ELSE (v_created_at AT TIME ZONE v_farm.timezone)::DATE END,
                CASE WHEN v_payload ? 'endsOn'
                          AND jsonb_typeof(v_payload -> 'endsOn') IS DISTINCT FROM 'null'
                     THEN (v_payload ->> 'endsOn')::DATE ELSE NULL END,
                'active', 1, v_created_at, v_created_at
            ) RETURNING * INTO v_row;

        ELSIF v_type = 'taskTemplate.update' THEN
            UPDATE public.task_templates AS template
               SET title = CASE WHEN v_payload ? 'title' THEN btrim(v_payload ->> 'title') ELSE template.title END,
                   zone_id = CASE WHEN v_payload ? 'zoneId'
                                  THEN CASE WHEN jsonb_typeof(v_payload -> 'zoneId') = 'null' THEN NULL
                                            ELSE (v_payload ->> 'zoneId')::UUID END
                                  ELSE template.zone_id END,
                   recurrence = CASE WHEN v_payload ? 'recurrence' THEN v_payload -> 'recurrence' ELSE template.recurrence END,
                   assignee_membership_id = CASE WHEN v_payload ? 'assigneeMembershipId'
                                  THEN CASE WHEN jsonb_typeof(v_payload -> 'assigneeMembershipId') = 'null' THEN NULL
                                            ELSE (v_payload ->> 'assigneeMembershipId')::UUID END
                                  ELSE template.assignee_membership_id END,
                   starts_on = CASE WHEN v_payload ? 'startsOn' THEN (v_payload ->> 'startsOn')::DATE ELSE template.starts_on END,
                   ends_on = CASE WHEN v_payload ? 'endsOn'
                                  THEN CASE WHEN jsonb_typeof(v_payload -> 'endsOn') = 'null' THEN NULL
                                            ELSE (v_payload ->> 'endsOn')::DATE END
                                  ELSE template.ends_on END,
                   status = CASE WHEN v_payload ? 'status' THEN v_payload ->> 'status' ELSE template.status END,
                   version = template.version + 1,
                   updated_at = v_created_at
             WHERE template.organization_id = p_organization_id
               AND template.farm_id = p_farm_id
               AND template.id = v_resource_id
             RETURNING template.* INTO v_row;

        ELSIF v_type IN ('taskOccurrence.transition', 'irrigationTask.transition') THEN
            UPDATE public.task_occurrences AS occurrence
               SET status = v_to_status,
                   completed_by = CASE WHEN v_transition = 'complete' THEN p_actor_pseudonym ELSE occurrence.completed_by END,
                   version = occurrence.version + 1,
                   updated_at = v_created_at
             WHERE occurrence.organization_id = p_organization_id
               AND occurrence.farm_id = p_farm_id
               AND occurrence.id = v_det_id
             RETURNING occurrence.* INTO v_occ;
            INSERT INTO public.task_transitions (
                organization_id, farm_id, id, occurrence_id, transition,
                from_status, to_status, reason, actor_pseudonym, operation_id, created_at
            ) VALUES (
                p_organization_id, p_farm_id, p_operation_id, v_det_id, v_transition,
                v_from_status, v_to_status,
                CASE WHEN v_payload ? 'reason' THEN v_payload ->> 'reason' ELSE NULL END,
                p_actor_pseudonym, p_operation_id, v_created_at
            );

        ELSIF v_type = 'harvest.create' THEN
            -- Head and first record share resourceId; the head->record FK is
            -- deferred so the head can be inserted first.
            INSERT INTO public.harvest_heads (
                organization_id, farm_id, harvest_id, planting_id,
                effective_record_id, status, version, created_at, updated_at
            ) VALUES (
                p_organization_id, p_farm_id, v_resource_id,
                (v_payload ->> 'plantingId')::UUID,
                v_resource_id, 'active', 1, v_created_at, v_created_at
            );
            INSERT INTO public.harvest_records (
                organization_id, farm_id, id, harvest_id, planting_id,
                quantity_kg, harvest_date, supersedes_record_id, operation_id, created_at
            ) VALUES (
                p_organization_id, p_farm_id, v_resource_id, v_resource_id,
                (v_payload ->> 'plantingId')::UUID,
                (v_payload ->> 'quantityKg')::NUMERIC(20, 4),
                (v_payload ->> 'harvestDate')::DATE,
                NULL, p_operation_id, v_created_at
            ) RETURNING * INTO v_row;
            SELECT * INTO v_head FROM public.harvest_heads AS head
             WHERE head.organization_id = p_organization_id
               AND head.farm_id = p_farm_id AND head.harvest_id = v_resource_id;

        ELSIF v_type = 'harvest.correction.propose' THEN
            v_hash := md5('corrprop:' || p_operation_id::TEXT);
            v_record_id := (substr(v_hash, 1, 8) || '-' || substr(v_hash, 9, 4)
                            || '-5' || substr(v_hash, 14, 3)
                            || '-8' || substr(v_hash, 18, 3)
                            || '-' || substr(v_hash, 21, 12))::UUID;
            INSERT INTO public.correction_proposals (
                organization_id, farm_id, id, harvest_id, proposed_quantity_kg,
                reason, proposed_by, status, operation_id, created_at
            ) VALUES (
                p_organization_id, p_farm_id, v_record_id, v_resource_id,
                (v_payload ->> 'proposedQuantityKg')::NUMERIC(20, 4),
                btrim(v_payload ->> 'reason'), p_actor_pseudonym, 'pending',
                p_operation_id, v_created_at
            ) RETURNING * INTO v_proposal;

        ELSIF v_type = 'harvest.correction.apply' THEN
            -- Append a correcting record; never UPDATE the original quantity.
            v_hash := md5('harvestrec:' || p_operation_id::TEXT);
            v_record_id := (substr(v_hash, 1, 8) || '-' || substr(v_hash, 9, 4)
                            || '-5' || substr(v_hash, 14, 3)
                            || '-8' || substr(v_hash, 18, 3)
                            || '-' || substr(v_hash, 21, 12))::UUID;
            INSERT INTO public.harvest_records (
                organization_id, farm_id, id, harvest_id, planting_id,
                quantity_kg, harvest_date, supersedes_record_id, reason,
                operation_id, created_at
            ) VALUES (
                p_organization_id, p_farm_id, v_record_id, v_resource_id,
                v_head.planting_id,
                (v_payload ->> 'proposedQuantityKg')::NUMERIC(20, 4),
                (SELECT record.harvest_date
                   FROM public.harvest_records AS record
                  WHERE record.organization_id = p_organization_id
                    AND record.farm_id = p_farm_id
                    AND record.id = v_head.effective_record_id),
                v_head.effective_record_id,
                CASE WHEN v_payload ? 'reason' THEN v_payload ->> 'reason' ELSE NULL END,
                p_operation_id, v_created_at
            ) RETURNING * INTO v_row;
            UPDATE public.harvest_heads AS head
               SET effective_record_id = v_record_id,
                   version = head.version + 1,
                   updated_at = v_created_at
             WHERE head.organization_id = p_organization_id
               AND head.farm_id = p_farm_id
               AND head.harvest_id = v_resource_id
             RETURNING head.* INTO v_head;
            IF v_payload ? 'proposalId' THEN
                UPDATE public.correction_proposals AS proposal
                   SET status = 'applied',
                       applied_operation_id = p_operation_id
                 WHERE proposal.organization_id = p_organization_id
                   AND proposal.farm_id = p_farm_id
                   AND proposal.id = (v_payload ->> 'proposalId')::UUID;
            END IF;

        ELSIF v_type = 'harvest.void' THEN
            UPDATE public.harvest_heads AS head
               SET status = 'voided',
                   void_reason = btrim(v_payload ->> 'reason'),
                   version = head.version + 1,
                   updated_at = v_created_at
             WHERE head.organization_id = p_organization_id
               AND head.farm_id = p_farm_id
               AND head.harvest_id = v_resource_id
             RETURNING head.* INTO v_head;

        ELSIF v_type = 'moistureReading.create' THEN
            INSERT INTO public.moisture_readings (
                organization_id, farm_id, id, zone_id, value, method, source,
                measured_at, operation_id, created_at
            ) VALUES (
                p_organization_id, p_farm_id, v_resource_id,
                (v_payload ->> 'zoneId')::UUID,
                (v_payload ->> 'value')::NUMERIC(5, 2),
                v_payload ->> 'method',
                'manual',
                v_measured,
                p_operation_id, v_created_at
            ) RETURNING * INTO v_row;

        ELSIF v_type = 'waterReading.create' THEN
            -- Snapshot capacity before the tank row variable is reused.
            v_capacity := v_row.capacity_litres;
            INSERT INTO public.water_readings (
                organization_id, farm_id, id, tank_id, stored_litres,
                capacity_snapshot_litres, source, measured_at, operation_id, created_at
            ) VALUES (
                p_organization_id, p_farm_id, v_resource_id,
                (v_payload ->> 'tankId')::UUID,
                (v_payload ->> 'storedLitres')::NUMERIC(20, 4),
                v_capacity,
                btrim(v_payload ->> 'source'),
                COALESCE(v_measured, v_created_at),
                p_operation_id, v_created_at
            ) RETURNING * INTO v_row;
            UPDATE public.water_tanks AS tank
               SET stored_litres = (v_payload ->> 'storedLitres')::NUMERIC(20, 4),
                   version = tank.version + 1,
                   updated_at = v_created_at
             WHERE tank.organization_id = p_organization_id
               AND tank.farm_id = p_farm_id
               AND tank.id = (v_payload ->> 'tankId')::UUID;

        ELSIF v_type = 'waterUsage.create' THEN
            INSERT INTO public.water_usages (
                organization_id, farm_id, id, tank_id, usage_litres,
                usage_date, note, operation_id, created_at
            ) VALUES (
                p_organization_id, p_farm_id, v_resource_id,
                (v_payload ->> 'tankId')::UUID,
                (v_payload ->> 'usageLitres')::NUMERIC(20, 4),
                (v_payload ->> 'usageDate')::DATE,
                CASE WHEN v_payload ? 'note' THEN v_payload ->> 'note' ELSE NULL END,
                p_operation_id, v_created_at
            ) RETURNING * INTO v_row;
        END IF;

        -- Refresh the written row for view building.
        IF v_type LIKE 'zone.%' THEN
            SELECT * INTO v_row FROM public.zones WHERE organization_id = p_organization_id AND farm_id = p_farm_id AND id = v_resource_id;
            v_view := jsonb_build_object(
                'id', v_row.id, 'version', v_row.version, 'type', v_row.type,
                'name', v_row.name, 'geometry', v_row.geometry,
                'areaM2', CASE WHEN v_row.area_m2 IS NULL THEN NULL ELSE v_row.area_m2::TEXT END,
                'status', v_row.status
            );
            v_view_key := 'zone';
        ELSIF v_type LIKE 'cropSpecies.%' THEN
            SELECT * INTO v_row FROM public.crop_species WHERE organization_id = p_organization_id AND farm_id = p_farm_id AND id = v_resource_id;
            v_view := jsonb_build_object(
                'id', v_row.id, 'version', v_row.version, 'name', v_row.name,
                'harvestUnit', v_row.harvest_unit, 'status', v_row.status
            );
            v_view_key := 'cropSpecies';
        ELSIF v_type LIKE 'planting.%' THEN
            SELECT * INTO v_row FROM public.plantings WHERE organization_id = p_organization_id AND farm_id = p_farm_id AND id = v_resource_id;
            v_view := jsonb_build_object(
                'id', v_row.id, 'version', v_row.version,
                'cropSpeciesId', v_row.crop_species_id, 'plotId', v_row.plot_id,
                'status', v_row.status,
                'sowingDate', to_char(v_row.sowing_date, 'YYYY-MM-DD'),
                'expectedHarvestDate', CASE WHEN v_row.expected_harvest_date IS NULL THEN NULL ELSE to_char(v_row.expected_harvest_date, 'YYYY-MM-DD') END,
                'areaM2', CASE WHEN v_row.area_m2 IS NULL THEN NULL ELSE v_row.area_m2::TEXT END
            );
            v_view_key := 'planting';
        ELSIF v_type LIKE 'herd.%' THEN
            SELECT * INTO v_row FROM public.herds WHERE organization_id = p_organization_id AND farm_id = p_farm_id AND id = v_resource_id;
            v_headcount := CASE WHEN v_row.mode = 'tracked' THEN
                (SELECT count(*)::INTEGER FROM public.animals AS animal
                  WHERE animal.organization_id = p_organization_id
                    AND animal.farm_id = p_farm_id AND animal.herd_id = v_row.id
                    AND animal.status = 'alive' AND NOT animal.archived)
            ELSE
                COALESCE((SELECT sum(movement.delta) FROM public.livestock_movements AS movement
                  WHERE movement.organization_id = p_organization_id
                    AND movement.farm_id = p_farm_id AND movement.herd_id = v_row.id), 0)::INTEGER
            END;
            v_view := jsonb_build_object(
                'id', v_row.id, 'version', v_row.version, 'mode', v_row.mode,
                'species', v_row.species, 'status', v_row.status, 'headcount', v_headcount
            );
            v_view_key := 'herd';
        ELSIF v_type LIKE 'animal.%' THEN
            SELECT * INTO v_row FROM public.animals WHERE organization_id = p_organization_id AND farm_id = p_farm_id AND id = v_resource_id;
            v_view := jsonb_build_object(
                'id', v_row.id, 'version', v_row.version, 'herdId', v_row.herd_id,
                'tag', v_row.tag, 'name', v_row.name,
                'birthDate', CASE WHEN v_row.birth_date IS NULL THEN NULL ELSE to_char(v_row.birth_date, 'YYYY-MM-DD') END,
                'status', v_row.status, 'archived', v_row.archived
            );
            v_view_key := 'animal';
        ELSIF v_type LIKE 'waterTank.%' THEN
            SELECT * INTO v_row FROM public.water_tanks WHERE organization_id = p_organization_id AND farm_id = p_farm_id AND id = v_resource_id;
            v_view := jsonb_build_object(
                'id', v_row.id, 'version', v_row.version, 'name', v_row.name,
                'zoneId', v_row.zone_id, 'capacityLitres', v_row.capacity_litres::TEXT,
                'storedLitres', CASE WHEN v_row.stored_litres IS NULL THEN NULL ELSE v_row.stored_litres::TEXT END,
                'status', v_row.status
            );
            v_view_key := 'waterTank';
        ELSIF v_type = 'plantingEvent.create' THEN
            v_view := jsonb_build_object(
                'id', v_row.id, 'version', 1, 'plantingId', v_row.planting_id,
                'eventType', v_row.event_type, 'note', v_row.note,
                'occurredOn', CASE WHEN v_row.occurred_on IS NULL THEN NULL
                                   ELSE to_char(v_row.occurred_on, 'YYYY-MM-DD') END);
            v_view_key := 'plantingEvent';
        ELSIF v_type = 'livestockMovement.create' THEN
            v_view := jsonb_build_object(
                'id', v_row.id, 'version', 1, 'herdId', v_row.herd_id,
                'movementType', v_row.movement_type, 'delta', v_row.delta,
                'occurredAt', v_row.occurred_at);
            v_view_key := 'livestockMovement';
        ELSIF v_type = 'animalObservation.create' THEN
            v_view := jsonb_build_object(
                'id', v_row.id, 'version', 1, 'herdId', v_row.herd_id,
                'animalId', v_row.animal_id, 'kind', v_row.kind,
                'note', v_row.note,
                'observedOn', CASE WHEN v_row.observed_on IS NULL THEN NULL
                                   ELSE to_char(v_row.observed_on, 'YYYY-MM-DD') END);
            v_view_key := 'animalObservation';
        ELSIF v_type = 'productionRecord.create' THEN
            v_view := jsonb_build_object(
                'id', v_row.id, 'version', 1, 'herdId', v_row.herd_id,
                'animalId', v_row.animal_id, 'product', v_row.product,
                'quantity', v_row.quantity::TEXT, 'unit', v_row.unit,
                'recordedOn', to_char(v_row.recorded_on, 'YYYY-MM-DD'));
            v_view_key := 'productionRecord';
        ELSIF v_type LIKE 'taskTemplate.%' THEN
            v_view := jsonb_build_object(
                'id', v_row.id, 'version', v_row.version, 'title', v_row.title,
                'kind', v_row.kind, 'zoneId', v_row.zone_id,
                'recurrence', v_row.recurrence,
                'assigneeMembershipId', v_row.assignee_membership_id,
                'startsOn', to_char(v_row.starts_on, 'YYYY-MM-DD'),
                'endsOn', CASE WHEN v_row.ends_on IS NULL THEN NULL
                               ELSE to_char(v_row.ends_on, 'YYYY-MM-DD') END,
                'status', v_row.status);
            v_view_key := 'taskTemplate';
        ELSIF v_type IN ('taskOccurrence.transition', 'irrigationTask.transition') THEN
            -- v_occ holds the post-transition row (RETURNING from the UPDATE).
            v_view := jsonb_build_object(
                'id', v_occ.id, 'version', v_occ.version,
                'templateId', v_occ.template_id,
                'occurrenceDate', to_char(v_occ.occurrence_date, 'YYYY-MM-DD'),
                'slot', v_occ.slot, 'status', v_occ.status,
                'dueAt', v_occ.due_at, 'completedBy', v_occ.completed_by);
            v_view_key := 'taskOccurrence';
            v_changes := jsonb_build_array(
                jsonb_build_object('entity', 'taskOccurrence', 'change', 'upsert', 'record', v_view),
                jsonb_build_object('entity', 'taskTransition', 'change', 'upsert', 'record',
                    jsonb_build_object(
                        'id', p_operation_id, 'occurrenceId', v_occ.id,
                        'transition', v_transition,
                        'fromStatus', v_from_status, 'toStatus', v_to_status,
                        'version', 1)));
        ELSIF v_type = 'harvest.correction.propose' THEN
            v_view := jsonb_build_object(
                'id', v_proposal.id, 'version', 1, 'harvestId', v_proposal.harvest_id,
                'proposedQuantityKg', v_proposal.proposed_quantity_kg::TEXT,
                'reason', v_proposal.reason, 'status', v_proposal.status);
            v_view_key := 'correctionProposal';
        ELSIF v_type LIKE 'harvest.%' THEN
            -- Head + effective record compose the canonical harvest view.
            SELECT * INTO v_row FROM public.harvest_records AS record
             WHERE record.organization_id = p_organization_id
               AND record.farm_id = p_farm_id
               AND record.id = v_head.effective_record_id;
            v_view := jsonb_build_object(
                'id', v_head.harvest_id, 'version', v_head.version,
                'plantingId', v_head.planting_id,
                'quantityKg', v_row.quantity_kg::TEXT,
                'harvestDate', to_char(v_row.harvest_date, 'YYYY-MM-DD'),
                'status', v_head.status);
            v_view_key := 'harvest';
            IF v_type = 'harvest.correction.apply' THEN
                v_changes := jsonb_build_array(
                    jsonb_build_object('entity', 'harvestRecord', 'change', 'upsert', 'record',
                        jsonb_build_object(
                            'id', v_row.id, 'harvestId', v_row.harvest_id,
                            'quantityKg', v_row.quantity_kg::TEXT,
                            'harvestDate', to_char(v_row.harvest_date, 'YYYY-MM-DD'),
                            'supersedesRecordId', v_row.supersedes_record_id,
                            'version', 1)),
                    jsonb_build_object('entity', 'harvest', 'change', 'upsert', 'record', v_view));
            END IF;
        ELSIF v_type = 'moistureReading.create' THEN
            v_view := jsonb_build_object(
                'id', v_row.id, 'version', 1, 'zoneId', v_row.zone_id,
                'value', v_row.value::TEXT, 'method', v_row.method,
                'source', v_row.source, 'measuredAt', v_row.measured_at);
            v_view_key := 'moistureReading';
        ELSIF v_type = 'waterReading.create' THEN
            v_view := jsonb_build_object(
                'id', v_row.id, 'version', 1, 'tankId', v_row.tank_id,
                'storedLitres', v_row.stored_litres::TEXT,
                'capacityLitres', v_row.capacity_snapshot_litres::TEXT,
                'source', v_row.source, 'measuredAt', v_row.measured_at);
            v_view_key := 'waterReading';
        ELSIF v_type = 'waterUsage.create' THEN
            v_view := jsonb_build_object(
                'id', v_row.id, 'version', 1, 'tankId', v_row.tank_id,
                'usageLitres', v_row.usage_litres::TEXT,
                'usageDate', to_char(v_row.usage_date, 'YYYY-MM-DD'),
                'note', v_row.note);
            v_view_key := 'waterUsage';
        ELSE
            -- farm.update / farm.archive
            v_view := jsonb_build_object(
                'farmId', v_farm.id, 'name', v_farm.name,
                'areaM2', CASE WHEN v_farm.area_m2 IS NULL THEN NULL ELSE v_farm.area_m2::TEXT END,
                'timezone', v_farm.timezone, 'location', v_farm.location,
                'status', v_farm.status, 'version', v_farm.version
            );
            v_view_key := 'farm';
        END IF;

        INSERT INTO public.change_sets (
            organization_id, farm_id, revision, continuity_epoch, actor_pseudonym,
            operation_id, schema_version, changes, created_at
        ) VALUES (
            p_organization_id, p_farm_id, v_revision, v_current_epoch, p_actor_pseudonym,
            p_operation_id, 'farm-change-set.v1',
            COALESCE(v_changes,
                jsonb_build_array(jsonb_build_object('entity', v_view_key, 'change', 'upsert', 'record', v_view))),
            v_created_at
        );
        INSERT INTO public.audit_events (
            organization_id, farm_id, actor_pseudonym, operation_id, action, revision, details, created_at
        ) VALUES (
            p_organization_id, p_farm_id, p_actor_pseudonym, p_operation_id,
            v_type, v_revision,
            jsonb_build_object('version', CASE WHEN v_view ? 'version' THEN v_view ->> 'version' ELSE NULL END),
            v_created_at
        );
    END IF;

    IF v_type = 'farm.create' THEN
        INSERT INTO public.change_sets (
            organization_id, farm_id, revision, continuity_epoch, actor_pseudonym,
            operation_id, schema_version, changes, created_at
        ) VALUES (
            p_organization_id, v_resource_id, v_revision, v_current_epoch, p_actor_pseudonym,
            p_operation_id, 'farm-change-set.v1',
            jsonb_build_array(jsonb_build_object('entity', 'farm', 'change', 'upsert', 'record', v_view)),
            v_created_at
        );
        INSERT INTO public.audit_events (
            organization_id, farm_id, actor_pseudonym, operation_id, action, revision, details, created_at
        ) VALUES (
            p_organization_id, v_resource_id, p_actor_pseudonym, p_operation_id,
            'farm.create', v_revision, jsonb_build_object('version', 1), v_created_at
        );
    END IF;

    v_result_data := jsonb_build_object(
        'operationId', p_operation_id,
        'outcome', 'applied',
        'revision', v_revision::TEXT
    );
    IF v_view_key = 'farm' THEN
        v_result_data := v_result_data || jsonb_build_object('farm', v_view);
    ELSE
        v_result_data := v_result_data || jsonb_build_object(v_view_key, v_view);
    END IF;

    UPDATE public.applied_operations
       SET outcome = 'applied',
           completed_at = v_created_at,
           result_version = CASE WHEN v_view ? 'version' THEN (v_view ->> 'version')::INTEGER ELSE 1 END
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

REVOKE ALL ON FUNCTION public.apply_farm_mutation(UUID, TEXT, TEXT, UUID, TEXT, BIGINT, JSONB, TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.apply_farm_mutation(UUID, TEXT, TEXT, UUID, TEXT, BIGINT, JSONB, TEXT, UUID) TO farmly_tenant_app;
