-- Follow-up: nested IF guard for the archive gate; plpgsql eagerly evaluates
-- fields of a never-assigned record inside SQL expressions.

DROP FUNCTION public.apply_farm_mutation(UUID, TEXT, TEXT, UUID, TEXT, BIGINT, JSONB, TEXT, UUID);

CREATE FUNCTION public.apply_farm_mutation(
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
        IF v_actor_role NOT IN ('owner', 'admin') THEN
            IF v_actor_role <> 'member'
               OR NOT EXISTS (
                   SELECT 1
                     FROM public.farm_grants AS grant_row
                    WHERE grant_row.organization_id = p_organization_id
                      AND grant_row.membership_id = v_membership_id
                      AND grant_row.farm_id = p_farm_id
                      AND grant_row.role = 'manager'
               ) THEN
                RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'FARMLY_PERMISSION_DENIED';
            END IF;
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
            'waterTank.create', 'waterTank.update', 'waterTank.archive'
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
        IF v_type LIKE '%.create' THEN
            IF p_intent ? 'baseVersion' AND p_intent -> 'baseVersion' <> 'null'::JSONB THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            END IF;
        ELSIF v_type LIKE '%.update' OR v_type LIKE '%.archive' THEN
            IF jsonb_typeof(p_intent -> 'baseVersion') IS DISTINCT FROM 'number'
               OR (p_intent ->> 'baseVersion') !~ '^[1-9][0-9]{0,9}$' THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSE
                v_base_version := (p_intent ->> 'baseVersion')::INTEGER;
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
               OR (v_payload - 'name' - 'areaM2' - 'timezone') <> '{}'::JSONB THEN
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
                ELSIF v_payload ? 'areaM2' THEN
                    v_area := (v_payload ->> 'areaM2')::NUMERIC(14, 2);
                END IF;
            END IF;

        ELSIF v_type IN ('farm.update', 'farm.archive') THEN
            IF jsonb_typeof(v_payload) IS DISTINCT FROM 'object' THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF v_type = 'farm.archive' AND v_payload <> '{}'::JSONB THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF v_type = 'farm.update' THEN
                IF (v_payload - 'name' - 'timezone' - 'areaM2') <> '{}'::JSONB
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

        v_view := jsonb_build_object(
            'farmId', v_resource_id,
            'name', v_name,
            'areaM2', CASE WHEN v_area IS NULL THEN NULL ELSE v_area::TEXT END,
            'timezone', v_timezone,
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
        ELSE
            -- farm.update / farm.archive
            v_view := jsonb_build_object(
                'farmId', v_farm.id, 'name', v_farm.name,
                'areaM2', CASE WHEN v_farm.area_m2 IS NULL THEN NULL ELSE v_farm.area_m2::TEXT END,
                'timezone', v_farm.timezone, 'status', v_farm.status, 'version', v_farm.version
            );
            v_view_key := 'farm';
        END IF;

        INSERT INTO public.change_sets (
            organization_id, farm_id, revision, continuity_epoch, actor_pseudonym,
            operation_id, schema_version, changes, created_at
        ) VALUES (
            p_organization_id, p_farm_id, v_revision, v_current_epoch, p_actor_pseudonym,
            p_operation_id, 'farm-change-set.v1',
            jsonb_build_array(jsonb_build_object('entity', v_view_key, 'change', 'upsert', 'record', v_view)),
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
