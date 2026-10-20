-- Keep IANA timezone validation inside the mutation kernel. The wrapped
-- function checks prior operation proofs before honoring a forced rejection,
-- preserving replay and operation-ID-reuse behavior for rejected writes.
ALTER FUNCTION public.apply_farm_mutation(
    UUID, TEXT, TEXT, UUID, TEXT, BIGINT, JSONB, TEXT, UUID
) RENAME TO apply_farm_mutation_without_iana_timezone_guard;

REVOKE ALL ON FUNCTION public.apply_farm_mutation_without_iana_timezone_guard(
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
    v_rejection_code TEXT := p_forced_rejection_code;
BEGIN
    IF v_rejection_code IS NULL
       AND (
           v_type = 'farm.create'
           OR (
               v_type = 'farm.update'
               AND COALESCE((p_intent -> 'payload') ? 'timezone', FALSE)
           )
       )
       AND (
           jsonb_typeof(p_intent #> '{payload,timezone}') IS DISTINCT FROM 'string'
           OR NOT EXISTS (
               SELECT 1
               FROM pg_catalog.pg_timezone_names AS timezone
               WHERE timezone.name = btrim(p_intent #>> '{payload,timezone}')
           )
       ) THEN
        v_rejection_code := 'FIELD_VALIDATION_FAILED';
    END IF;

    RETURN QUERY
    SELECT *
    FROM public.apply_farm_mutation_without_iana_timezone_guard(
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
