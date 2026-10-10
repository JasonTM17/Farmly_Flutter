-- P08: farm bootstrap snapshots + signed-cursor change feed support.
--
-- Bootstrap snapshots are private per creator (actor_pseudonym binding is
-- enforced in the service layer on top of farm-scoped RLS), immutable once
-- written, and carry a fixed 15-minute TTL from creation (spec04 §7).
-- Chunk payloads are prebuilt by the service inside one REPEATABLE READ
-- transaction; this migration only adds storage, RLS, cap enforcement and
-- the retention floor function.

CREATE TABLE public.bootstrap_snapshots (
    organization_id UUID NOT NULL,
    farm_id UUID NOT NULL,
    id UUID NOT NULL,
    actor_pseudonym CHAR(64) NOT NULL CHECK (actor_pseudonym ~ '^[a-f0-9]{64}$'),
    scope_policy_version BIGINT NOT NULL CHECK (scope_policy_version >= 1),
    continuity_epoch BIGINT NOT NULL CHECK (continuity_epoch >= 1),
    high_watermark BIGINT NOT NULL CHECK (high_watermark >= 0),
    pruned_through_revision BIGINT NOT NULL DEFAULT 0 CHECK (pruned_through_revision >= 0),
    row_count INTEGER NOT NULL CHECK (row_count >= 0),
    byte_count INTEGER NOT NULL CHECK (byte_count >= 0),
    chunk_count INTEGER NOT NULL CHECK (chunk_count >= 1),
    created_at TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ(6) NOT NULL,
    CONSTRAINT bootstrap_snapshots_pkey PRIMARY KEY (organization_id, farm_id, id),
    CONSTRAINT bootstrap_snapshots_farm_fkey FOREIGN KEY (organization_id, farm_id)
        REFERENCES public.farms(organization_id, id) ON DELETE CASCADE,
    CONSTRAINT bootstrap_snapshots_expiry_order CHECK (expires_at > created_at)
);

CREATE TABLE public.bootstrap_snapshot_chunks (
    organization_id UUID NOT NULL,
    farm_id UUID NOT NULL,
    snapshot_id UUID NOT NULL,
    page_index INTEGER NOT NULL CHECK (page_index >= 1),
    row_count INTEGER NOT NULL CHECK (row_count >= 1),
    payload JSONB NOT NULL CHECK (jsonb_typeof(payload) = 'array'),
    CONSTRAINT bootstrap_snapshot_chunks_pkey PRIMARY KEY (organization_id, farm_id, snapshot_id, page_index),
    CONSTRAINT bootstrap_snapshot_chunks_snapshot_fkey FOREIGN KEY (organization_id, farm_id, snapshot_id)
        REFERENCES public.bootstrap_snapshots(organization_id, farm_id, id) ON DELETE CASCADE
);

ALTER TABLE public.bootstrap_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bootstrap_snapshots FORCE ROW LEVEL SECURITY;
CREATE POLICY bootstrap_snapshots_migration_access ON public.bootstrap_snapshots
    TO farmly_migration USING (TRUE) WITH CHECK (TRUE);
CREATE POLICY bootstrap_snapshots_tenant_read ON public.bootstrap_snapshots
    FOR SELECT TO farmly_tenant_app
    USING (public.farmly_actor_can_read_farm(organization_id, farm_id));

ALTER TABLE public.bootstrap_snapshot_chunks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bootstrap_snapshot_chunks FORCE ROW LEVEL SECURITY;
CREATE POLICY bootstrap_snapshot_chunks_migration_access ON public.bootstrap_snapshot_chunks
    TO farmly_migration USING (TRUE) WITH CHECK (TRUE);
CREATE POLICY bootstrap_snapshot_chunks_tenant_read ON public.bootstrap_snapshot_chunks
    FOR SELECT TO farmly_tenant_app
    USING (public.farmly_actor_can_read_farm(organization_id, farm_id));

-- The change feed and farm clock become tenant-readable so sync/changes and
-- bootstrap can serve them under the standard farm-read grant. Writes stay
-- migration-role only (kernel + pruning function).
CREATE POLICY farm_clocks_tenant_read ON public.farm_clocks
    FOR SELECT TO farmly_tenant_app
    USING (public.farmly_actor_can_read_farm(organization_id, farm_id));
CREATE POLICY change_sets_tenant_read ON public.change_sets
    FOR SELECT TO farmly_tenant_app
    USING (public.farmly_actor_can_read_farm(organization_id, farm_id));

-- Policies alone do not convey table privilege: pair them with explicit
-- read grants exactly like the domain-resource migration does.
REVOKE ALL ON TABLE public.bootstrap_snapshots, public.bootstrap_snapshot_chunks
    FROM PUBLIC, farmly_auth_app, farmly_tenant_app;
GRANT SELECT ON TABLE public.bootstrap_snapshots, public.bootstrap_snapshot_chunks
    TO farmly_tenant_app;
GRANT SELECT ON TABLE public.change_sets, public.farm_clocks
    TO farmly_tenant_app;

-- The bootstrap writer runs nested authorization checks, so the inner
-- helper needs an explicit grant for the migration definer role.
GRANT EXECUTE ON FUNCTION public.farmly_actor_can_read_farm(UUID, UUID) TO farmly_migration;

-- Materializes a prebuilt chunk set for one farm snapshot. The caller's
-- transaction supplies the consistent view (the service runs this inside a
-- REPEATABLE READ tx alongside the domain reads). Caps are fail-closed:
-- exceeding maxRows/maxBytes raises BOOTSTRAP_TOO_LARGE with nothing written.
CREATE FUNCTION public.farmly_write_bootstrap_snapshot(
    p_organization_id UUID,
    p_farm_id UUID,
    p_snapshot_id UUID,
    p_actor_pseudonym TEXT,
    p_scope_policy_version BIGINT,
    p_continuity_epoch BIGINT,
    p_high_watermark BIGINT,
    p_pruned_through_revision BIGINT,
    p_chunks JSONB,
    p_ttl_seconds INTEGER,
    p_max_rows INTEGER,
    p_max_bytes INTEGER
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_chunk JSONB;
    v_page_index INTEGER;
    v_row_count INTEGER;
    v_total_rows BIGINT := 0;
    v_total_bytes BIGINT := 0;
    v_chunk_count INTEGER := 0;
    v_expires_at TIMESTAMPTZ(6);
    v_existing JSONB;
BEGIN
    IF p_actor_pseudonym !~ '^[a-f0-9]{64}$' THEN
        RAISE EXCEPTION 'FARMLY_ACTOR_BINDING_INVALID';
    END IF;
    IF NOT public.farmly_actor_can_read_farm(p_organization_id, p_farm_id) THEN
        RAISE EXCEPTION 'FARMLY_ACCESS_REVOKED';
    END IF;
    IF jsonb_typeof(p_chunks) IS DISTINCT FROM 'array' OR jsonb_array_length(p_chunks) < 1 THEN
        RAISE EXCEPTION 'FARMLY_BOOTSTRAP_NO_CHUNKS';
    END IF;

    -- Idempotent on the request's operationId-as-snapshot-id: a retried
    -- bootstrap returns the already-materialized manifest for the same
    -- actor+scope instead of duplicating chunks.
    SELECT jsonb_build_object(
               'snapshotId', s.id, 'expiresAt', s.expires_at,
               'rowCount', s.row_count, 'byteCount', s.byte_count,
               'chunkCount', s.chunk_count, 'replayed', TRUE)
      INTO v_existing
      FROM public.bootstrap_snapshots AS s
     WHERE s.organization_id = p_organization_id AND s.farm_id = p_farm_id
       AND s.id = p_snapshot_id AND s.actor_pseudonym = p_actor_pseudonym;
    IF v_existing IS NOT NULL THEN
        RETURN v_existing;
    END IF;

    FOR v_chunk IN SELECT value FROM jsonb_array_elements(p_chunks) LOOP
        v_page_index := (v_chunk->>'pageIndex')::INTEGER;
        v_row_count := (v_chunk->>'rowCount')::INTEGER;
        v_chunk_count := v_chunk_count + 1;
        v_total_rows := v_total_rows + v_row_count;
        v_total_bytes := v_total_bytes + octet_length((v_chunk->'payload')::TEXT);
        IF v_page_index IS NULL OR v_page_index <> v_chunk_count
           OR v_row_count IS NULL OR v_row_count < 1
           OR jsonb_typeof(v_chunk->'payload') IS DISTINCT FROM 'array' THEN
            RAISE EXCEPTION 'FARMLY_BOOTSTRAP_CHUNK_INVALID';
        END IF;
    END LOOP;

    IF v_total_rows > p_max_rows OR v_total_bytes > p_max_bytes THEN
        RAISE EXCEPTION 'BOOTSTRAP_TOO_LARGE';
    END IF;

    v_expires_at := CURRENT_TIMESTAMP + make_interval(secs => p_ttl_seconds);

    INSERT INTO public.bootstrap_snapshots (
        organization_id, farm_id, id, actor_pseudonym,
        scope_policy_version, continuity_epoch, high_watermark,
        pruned_through_revision, row_count, byte_count, chunk_count, expires_at
    ) VALUES (
        p_organization_id, p_farm_id, p_snapshot_id, p_actor_pseudonym,
        p_scope_policy_version, p_continuity_epoch, p_high_watermark,
        p_pruned_through_revision, v_total_rows, v_total_bytes, v_chunk_count, v_expires_at
    );

    FOR v_chunk IN SELECT value FROM jsonb_array_elements(p_chunks) LOOP
        INSERT INTO public.bootstrap_snapshot_chunks (
            organization_id, farm_id, snapshot_id, page_index, row_count, payload
        ) VALUES (
            p_organization_id, p_farm_id, p_snapshot_id,
            (v_chunk->>'pageIndex')::INTEGER, (v_chunk->>'rowCount')::INTEGER,
            v_chunk->'payload'
        );
    END LOOP;

    RETURN jsonb_build_object(
        'snapshotId', p_snapshot_id,
        'expiresAt', v_expires_at,
        'rowCount', v_total_rows,
        'byteCount', v_total_bytes,
        'chunkCount', v_chunk_count,
        'replayed', FALSE
    );
END;
$$;

REVOKE ALL ON FUNCTION public.farmly_write_bootstrap_snapshot(UUID, UUID, UUID, TEXT, BIGINT, BIGINT, BIGINT, BIGINT, JSONB, INTEGER, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.farmly_write_bootstrap_snapshot(UUID, UUID, UUID, TEXT, BIGINT, BIGINT, BIGINT, BIGINT, JSONB, INTEGER, INTEGER, INTEGER) TO farmly_tenant_app;
GRANT EXECUTE ON FUNCTION public.farmly_write_bootstrap_snapshot(UUID, UUID, UUID, TEXT, BIGINT, BIGINT, BIGINT, BIGINT, JSONB, INTEGER, INTEGER, INTEGER) TO farmly_migration;

-- Retention pruning (control-plane): advances pruned_through_revision and
-- deletes the corresponding complete change sets under the same farm-clock
-- lock the mutation kernel holds through commit, so no partially removed or
-- skipped revision can be observed (spec04 §208).
CREATE FUNCTION public.farmly_prune_change_sets(
    p_organization_id UUID,
    p_farm_id UUID,
    p_through_revision BIGINT
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_revision BIGINT;
    v_floor BIGINT;
    v_new_floor BIGINT;
BEGIN
    SELECT clock.revision, clock.pruned_through_revision
      INTO v_revision, v_floor
      FROM public.farm_clocks AS clock
     WHERE clock.organization_id = p_organization_id AND clock.farm_id = p_farm_id
     FOR UPDATE;
    IF v_revision IS NULL THEN
        RAISE EXCEPTION 'FARMLY_ACCESS_REVOKED';
    END IF;

    v_new_floor := LEAST(GREATEST(p_through_revision, 0), v_revision);
    IF v_new_floor > v_floor THEN
        -- A change set is one row per committed revision, so deleting
        -- revision <= floor removes complete sets only.
        DELETE FROM public.change_sets
         WHERE organization_id = p_organization_id AND farm_id = p_farm_id
           AND revision > v_floor AND revision <= v_new_floor;
        UPDATE public.farm_clocks
           SET pruned_through_revision = v_new_floor,
               updated_at = CURRENT_TIMESTAMP
         WHERE organization_id = p_organization_id AND farm_id = p_farm_id;
    END IF;
    RETURN v_new_floor;
END;
$$;

REVOKE ALL ON FUNCTION public.farmly_prune_change_sets(UUID, UUID, BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.farmly_prune_change_sets(UUID, UUID, BIGINT) TO farmly_migration;
