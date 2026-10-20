-- Existing animal tags are canonicalized with btrim only. Fail without
-- changing any rows when historical farm-local collisions need reconciliation.
DO $animal_tag_preflight$
BEGIN
    IF EXISTS (
        SELECT 1
          FROM public.animals AS animal
         GROUP BY animal.organization_id, animal.farm_id, btrim(animal.tag)
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION USING
            ERRCODE = '23514',
            MESSAGE = 'animal tag uniqueness preflight found duplicate canonical tags';
    END IF;
END;
$animal_tag_preflight$;

-- Archived animals retain their tags. Default text equality preserves case;
-- no lowercasing or Unicode normalization is introduced.
CREATE UNIQUE INDEX animals_org_farm_trimmed_tag_uq
    ON public.animals (organization_id, farm_id, btrim(tag));

ALTER FUNCTION public.apply_farm_mutation(
    UUID, TEXT, TEXT, UUID, TEXT, BIGINT, JSONB, TEXT, UUID
) RENAME TO apply_farm_mutation_without_animal_tag_guard;

REVOKE ALL ON FUNCTION public.apply_farm_mutation_without_animal_tag_guard(
    UUID, TEXT, TEXT, UUID, TEXT, BIGINT, JSONB, TEXT, UUID
) FROM PUBLIC, farmly_tenant_app;

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
    v_type TEXT := p_intent ->> 'type';
    v_payload JSONB := p_intent -> 'payload';
    v_rejection_code TEXT := p_forced_rejection_code;
    v_organization_status public.organization_status;
    v_organization_epoch BIGINT;
    v_actor_role public.organization_role;
    v_membership_id UUID;
    v_farm_write TEXT;
    v_farm_status TEXT;
    v_clock_epoch BIGINT;
    v_resource_id UUID;
    v_herd_id UUID;
    v_base_version INTEGER;
    v_tag TEXT;
    v_date DATE;
    v_animal RECORD;
    v_herd RECORD;
    v_guardable BOOLEAN := FALSE;
    v_has_operation_proof BOOLEAN := FALSE;
    v_duplicate_tag BOOLEAN := FALSE;
    v_resource_exists BOOLEAN := FALSE;
BEGIN
    -- Guard only a fully well-formed, authorized, current operation. The inner
    -- kernel remains authoritative for malformed requests, denials, CAS,
    -- durable operation replay, and every non-tag animal mutation.
    IF v_rejection_code IS NULL
       AND p_organization_id IS NOT NULL
       AND p_actor_id IS NOT NULL
       AND NULLIF(current_setting('app.actor_id', TRUE), '') IS NOT DISTINCT FROM p_actor_id
       AND p_operation_id IS NOT NULL
       AND p_intent ->> 'operationId' IS NOT DISTINCT FROM p_operation_id::TEXT
       AND p_actor_pseudonym ~ '^[a-f0-9]{64}$'
       AND p_request_hash ~ '^[a-f0-9]{64}$'
       AND p_continuity_epoch IS NOT NULL
       AND p_continuity_epoch > 0
       AND p_farm_id IS NOT NULL
       AND v_type IN ('animal.create', 'animal.update')
       AND jsonb_typeof(v_payload) = 'object'
       AND p_intent ->> 'resourceId' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       AND p_intent ->> 'continuityEpoch' = p_continuity_epoch::TEXT THEN
        v_resource_id := (p_intent ->> 'resourceId')::UUID;

        SELECT organization.status, organization.continuity_epoch
          INTO v_organization_status, v_organization_epoch
          FROM public.organizations AS organization
         WHERE organization.id = p_organization_id
         FOR UPDATE;

        IF FOUND AND v_organization_status = 'active'
           AND v_organization_epoch = p_continuity_epoch THEN
            SELECT membership.role, membership.id
              INTO v_actor_role, v_membership_id
              FROM public.organization_memberships AS membership
             WHERE membership.organization_id = p_organization_id
               AND membership.user_id = p_actor_id
               AND membership.status = 'active';

            v_farm_write := NULL;
            IF v_actor_role IN ('owner', 'admin') THEN
                v_farm_write := 'manager';
            ELSIF v_actor_role = 'member' THEN
                SELECT grant_row.role::TEXT
                  INTO v_farm_write
                  FROM public.farm_grants AS grant_row
                 WHERE grant_row.organization_id = p_organization_id
                   AND grant_row.membership_id = v_membership_id
                   AND grant_row.farm_id = p_farm_id
                   AND grant_row.role IN ('manager', 'worker')
                 ORDER BY CASE grant_row.role WHEN 'manager' THEN 1 ELSE 2 END
                 LIMIT 1;
            END IF;

            IF v_actor_role IN ('owner', 'admin') OR v_farm_write IS NOT NULL THEN
                SELECT farm.status::TEXT
                  INTO v_farm_status
                  FROM public.farms AS farm
                 WHERE farm.organization_id = p_organization_id
                   AND farm.id = p_farm_id
                 FOR UPDATE;

                IF FOUND AND v_farm_status = 'active' AND v_farm_write = 'manager' THEN
                    -- Durable replays and operation-ID reuse go through the
                    -- existing kernel unchanged before any new collision check.
                    SELECT EXISTS (
                        SELECT 1
                          FROM public.applied_operations AS operation
                         WHERE operation.organization_id = p_organization_id
                           AND operation.actor_pseudonym = p_actor_pseudonym
                           AND operation.operation_id = p_operation_id
                    ) INTO v_has_operation_proof;

                    IF NOT v_has_operation_proof THEN
                        -- This row lock is the farm-local serialization point:
                        -- org -> farm -> FarmClock -> resource. The unique index
                        -- remains the backstop for writes outside this wrapper.
                        SELECT clock.continuity_epoch
                          INTO v_clock_epoch
                          FROM public.farm_clocks AS clock
                         WHERE clock.organization_id = p_organization_id
                           AND clock.farm_id = p_farm_id
                         FOR UPDATE;

                        IF FOUND AND v_clock_epoch = p_continuity_epoch THEN
                            IF v_type = 'animal.create'
                               AND v_payload ? 'tag'
                               AND v_payload ? 'herdId'
                               AND NOT (p_intent ? 'baseVersion'
                                   AND p_intent -> 'baseVersion' <> 'null'::JSONB)
                               AND (v_payload - 'herdId' - 'tag' - 'name' - 'birthDate' - 'status') = '{}'::JSONB
                               AND jsonb_typeof(v_payload -> 'tag') = 'string'
                               AND jsonb_typeof(v_payload -> 'herdId') = 'string'
                               AND v_payload ->> 'herdId' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
                                v_tag := btrim(v_payload ->> 'tag');
                                v_herd_id := (v_payload ->> 'herdId')::UUID;
                                v_guardable := length(v_tag) BETWEEN 1 AND 64;

                                IF v_guardable AND v_payload ? 'name' THEN
                                    v_guardable := jsonb_typeof(v_payload -> 'name') = 'string'
                                        AND length(btrim(v_payload ->> 'name')) BETWEEN 1 AND 160;
                                END IF;
                                IF v_guardable AND v_payload ? 'status'
                                   AND v_payload -> 'status' <> 'null'::JSONB THEN
                                    v_guardable := jsonb_typeof(v_payload -> 'status') = 'string'
                                        AND v_payload ->> 'status' IN ('alive', 'sold', 'deceased');
                                END IF;
                                IF v_guardable AND v_payload ? 'birthDate' THEN
                                    v_guardable := jsonb_typeof(v_payload -> 'birthDate') = 'string'
                                        AND v_payload ->> 'birthDate' ~ '^\d{4}-\d{2}-\d{2}$';
                                    IF v_guardable THEN
                                        BEGIN
                                            v_date := (v_payload ->> 'birthDate')::DATE;
                                        EXCEPTION WHEN OTHERS THEN
                                            v_guardable := FALSE;
                                        END;
                                    END IF;
                                END IF;

                                IF v_guardable THEN
                                    SELECT herd.status::TEXT, herd.mode::TEXT
                                      INTO v_herd
                                      FROM public.herds AS herd
                                     WHERE herd.organization_id = p_organization_id
                                       AND herd.farm_id = p_farm_id
                                       AND herd.id = v_herd_id
                                     FOR UPDATE;
                                    v_guardable := FOUND
                                        AND v_herd.status = 'active'
                                        AND v_herd.mode = 'tracked';
                                END IF;

                                IF v_guardable THEN
                                    SELECT EXISTS (
                                        SELECT 1
                                          FROM public.animals AS animal
                                         WHERE animal.organization_id = p_organization_id
                                           AND animal.farm_id = p_farm_id
                                           AND animal.id = v_resource_id
                                    ) INTO v_resource_exists;
                                    IF NOT v_resource_exists THEN
                                        SELECT EXISTS (
                                            SELECT 1
                                              FROM public.animals AS animal
                                             WHERE animal.organization_id = p_organization_id
                                               AND animal.farm_id = p_farm_id
                                               AND btrim(animal.tag) = v_tag
                                        ) INTO v_duplicate_tag;
                                    END IF;
                                END IF;
                            ELSIF v_type = 'animal.update'
                                  AND v_payload ? 'tag'
                                  AND (v_payload - 'tag' - 'name' - 'birthDate' - 'status') = '{}'::JSONB
                                  AND jsonb_typeof(v_payload -> 'tag') = 'string'
                                  AND jsonb_typeof(p_intent -> 'baseVersion') = 'number'
                                  AND p_intent ->> 'baseVersion' ~ '^[1-9][0-9]{0,9}$' THEN
                                v_tag := btrim(v_payload ->> 'tag');
                                v_guardable := length(v_tag) BETWEEN 1 AND 64
                                    AND (p_intent ->> 'baseVersion')::NUMERIC <= 2147483647;
                                IF v_guardable AND v_payload ? 'name' THEN
                                    v_guardable := jsonb_typeof(v_payload -> 'name') = 'string'
                                        AND length(btrim(v_payload ->> 'name')) BETWEEN 1 AND 160;
                                END IF;
                                IF v_guardable AND v_payload ? 'status'
                                   AND v_payload -> 'status' <> 'null'::JSONB THEN
                                    v_guardable := jsonb_typeof(v_payload -> 'status') = 'string'
                                        AND v_payload ->> 'status' IN ('alive', 'sold', 'deceased');
                                END IF;
                                IF v_guardable AND v_payload ? 'birthDate' THEN
                                    v_guardable := jsonb_typeof(v_payload -> 'birthDate') = 'string'
                                        AND v_payload ->> 'birthDate' ~ '^\d{4}-\d{2}-\d{2}$';
                                    IF v_guardable THEN
                                        BEGIN
                                            v_date := (v_payload ->> 'birthDate')::DATE;
                                        EXCEPTION WHEN OTHERS THEN
                                            v_guardable := FALSE;
                                        END;
                                    END IF;
                                END IF;

                                IF v_guardable THEN
                                    v_base_version := (p_intent ->> 'baseVersion')::INTEGER;
                                    SELECT animal.version, animal.archived
                                      INTO v_animal
                                      FROM public.animals AS animal
                                     WHERE animal.organization_id = p_organization_id
                                       AND animal.farm_id = p_farm_id
                                       AND animal.id = v_resource_id
                                     FOR UPDATE;
                                    v_guardable := FOUND
                                        AND v_animal.version = v_base_version
                                        AND NOT v_animal.archived;
                                END IF;

                                IF v_guardable THEN
                                    SELECT EXISTS (
                                        SELECT 1
                                          FROM public.animals AS animal
                                         WHERE animal.organization_id = p_organization_id
                                           AND animal.farm_id = p_farm_id
                                           AND animal.id <> v_resource_id
                                           AND btrim(animal.tag) = v_tag
                                    ) INTO v_duplicate_tag;
                                END IF;
                            END IF;

                            IF v_guardable AND v_duplicate_tag THEN
                                v_rejection_code := 'FIELD_VALIDATION_FAILED';
                            END IF;
                        END IF;
                    END IF;
                END IF;
            END IF;
        END IF;
    END IF;

    RETURN QUERY
    SELECT *
      FROM public.apply_farm_mutation_without_animal_tag_guard(
          p_organization_id,
          p_actor_id,
          p_actor_pseudonym,
          p_operation_id,
          p_request_hash,
          p_continuity_epoch,
          p_intent,
          v_rejection_code,
          p_farm_id
      );
END;
$$;

REVOKE ALL ON FUNCTION public.apply_farm_mutation(
    UUID, TEXT, TEXT, UUID, TEXT, BIGINT, JSONB, TEXT, UUID
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.apply_farm_mutation(
    UUID, TEXT, TEXT, UUID, TEXT, BIGINT, JSONB, TEXT, UUID
) TO farmly_tenant_app;
