-- Keep weekly recurrence requirements and occurrence-day matching in the
-- mutation boundary. Existing operation proofs are still resolved by the
-- inner IANA guard before a forced field rejection is returned.
ALTER FUNCTION public.apply_farm_mutation(
    UUID, TEXT, TEXT, UUID, TEXT, BIGINT, JSONB, TEXT, UUID
) RENAME TO apply_farm_mutation_without_task_schedule_guard;

REVOKE ALL ON FUNCTION public.apply_farm_mutation_without_task_schedule_guard(
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
    v_recurrence JSONB;
    v_rejection_code TEXT := p_forced_rejection_code;
    v_organization_status public.organization_status;
    v_actor_role public.organization_role;
    v_membership_id UUID;
    v_farm_write TEXT;
    v_farm_status TEXT;
    v_template_id UUID;
    v_occurrence_date DATE;
    v_slot TEXT;
    v_transition TEXT;
    v_template RECORD;
    v_existing_occurrence BOOLEAN := FALSE;
    v_weekday INTEGER;
BEGIN
    -- Weekly schedules are complete replacements: they must explicitly select
    -- at least one farm-local weekday. Leave malformed envelopes and other
    -- recurrence validation to the established mutation kernel.
    IF v_rejection_code IS NULL
       AND v_type IN ('taskTemplate.create', 'taskTemplate.update')
       AND jsonb_typeof(v_payload) = 'object'
       AND jsonb_typeof(v_payload -> 'recurrence') = 'object' THEN
        v_recurrence := v_payload -> 'recurrence';
        IF v_recurrence ->> 'freq' = 'weekly' THEN
            IF NOT (v_recurrence ? 'daysOfWeek')
               OR jsonb_typeof(v_recurrence -> 'daysOfWeek') IS DISTINCT FROM 'array' THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            ELSIF jsonb_array_length(v_recurrence -> 'daysOfWeek') = 0 THEN
                v_rejection_code := 'FIELD_VALIDATION_FAILED';
            END IF;
        END IF;
    END IF;

    -- For an unmaterialized occurrence, serialize with schedule edits and
    -- revocation using the same organization -> farm -> template lock order as
    -- the kernel. Re-read membership and effective farm write access after the
    -- organization lock, before taking any farm/template lock or reading task
    -- state. Non-guardable requests are delegated unchanged so the kernel keeps
    -- its existing validation and denial behavior.
    IF v_rejection_code IS NULL
       AND v_type IN ('taskOccurrence.transition', 'irrigationTask.transition')
       AND p_organization_id IS NOT NULL
       AND p_actor_id IS NOT NULL
       AND NULLIF(current_setting('app.actor_id', TRUE), '') IS NOT DISTINCT FROM p_actor_id
       AND p_operation_id IS NOT NULL
       AND p_intent ->> 'operationId' IS NOT DISTINCT FROM p_operation_id::TEXT
       AND p_farm_id IS NOT NULL
       AND jsonb_typeof(v_payload) = 'object'
       AND jsonb_typeof(v_payload -> 'templateId') = 'string'
       AND (v_payload ->> 'templateId') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       AND jsonb_typeof(v_payload -> 'occurrenceDate') = 'string'
       AND (v_payload ->> 'occurrenceDate') ~ '^\d{4}-\d{2}-\d{2}$'
       AND jsonb_typeof(v_payload -> 'slot') = 'string'
       AND length(btrim(v_payload ->> 'slot')) BETWEEN 1 AND 40 THEN
        BEGIN
            v_template_id := (v_payload ->> 'templateId')::UUID;
            v_occurrence_date := (v_payload ->> 'occurrenceDate')::DATE;
            v_slot := btrim(v_payload ->> 'slot');
            v_transition := v_payload ->> 'transition';
        EXCEPTION WHEN OTHERS THEN
            -- The established kernel returns the canonical validation result.
            v_template_id := NULL;
            v_occurrence_date := NULL;
        END;

        IF v_template_id IS NOT NULL AND v_occurrence_date IS NOT NULL THEN
            SELECT organization.status
              INTO v_organization_status
              FROM public.organizations AS organization
             WHERE organization.id = p_organization_id
             FOR UPDATE;

            IF FOUND AND v_organization_status = 'active' THEN
                SELECT membership.role, membership.id
                  INTO v_actor_role, v_membership_id
                  FROM public.organization_memberships AS membership
                 WHERE membership.organization_id = p_organization_id
                   AND membership.user_id = p_actor_id
                   AND membership.status = 'active';

                IF FOUND THEN
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

                    IF v_farm_write IS NOT NULL THEN
                        SELECT farm.status::TEXT
                          INTO v_farm_status
                          FROM public.farms AS farm
                         WHERE farm.organization_id = p_organization_id
                           AND farm.id = p_farm_id
                         FOR UPDATE;

                        -- Let the kernel own the canonical archived/missing-farm
                        -- result. A schedule rejection must not mask it.
                        IF FOUND AND v_farm_status = 'active' THEN
                            SELECT template.*
                              INTO v_template
                              FROM public.task_templates AS template
                             WHERE template.organization_id = p_organization_id
                               AND template.farm_id = p_farm_id
                               AND template.id = v_template_id
                             FOR UPDATE;

                            IF FOUND AND v_template.status = 'active'
                               AND (v_type <> 'irrigationTask.transition' OR v_template.kind = 'irrigation')
                               AND NOT (
                                   (v_transition IN ('reopen', 'cancel') AND v_farm_write <> 'manager')
                                   OR (
                                       v_transition IN ('complete', 'skip')
                                       AND v_farm_write = 'worker'
                                       AND v_template.assignee_membership_id IS NOT NULL
                                       AND v_template.assignee_membership_id IS DISTINCT FROM v_membership_id
                                   )
                               ) THEN
                                SELECT EXISTS (
                                    SELECT 1
                                      FROM public.task_occurrences AS occurrence
                                     WHERE occurrence.organization_id = p_organization_id
                                       AND occurrence.farm_id = p_farm_id
                                       AND occurrence.template_id = v_template_id
                                       AND occurrence.occurrence_date = v_occurrence_date
                                       AND occurrence.slot = v_slot
                                ) INTO v_existing_occurrence;

                                IF NOT v_existing_occurrence
                                   AND v_template.recurrence ->> 'freq' = 'weekly' THEN
                                    v_weekday := EXTRACT(DOW FROM v_occurrence_date)::INTEGER;
                                    IF jsonb_typeof(v_template.recurrence -> 'daysOfWeek') IS DISTINCT FROM 'array' THEN
                                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                                    ELSIF jsonb_array_length(v_template.recurrence -> 'daysOfWeek') = 0
                                       OR NOT EXISTS (
                                           SELECT 1
                                             FROM jsonb_array_elements(v_template.recurrence -> 'daysOfWeek') AS selected(day)
                                            WHERE selected.day = to_jsonb(v_weekday)
                                       ) THEN
                                        v_rejection_code := 'FIELD_VALIDATION_FAILED';
                                    END IF;
                                END IF;
                            END IF;
                        END IF;
                    END IF;
                END IF;
            END IF;
        END IF;
    END IF;

    RETURN QUERY
    SELECT *
      FROM public.apply_farm_mutation_without_task_schedule_guard(
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
