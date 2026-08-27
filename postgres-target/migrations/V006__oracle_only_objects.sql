-- V006: PostgreSQL treatment for the Oracle-only storage choices.
--
-- Four constructs are handled here: the index-organized table, the synonym,
-- the materialized view, and the global temporary table. The bitmap index is
-- handled in V004 next to the other indexes.

-- 1. Index-organized table (retail.order_lines).
--
-- No PostgreSQL equivalent. The table is an ordinary heap; marking the primary
-- key as the CLUSTER index gives the same physical ordering whenever CLUSTER or
-- pg_repack runs. Unlike Oracle this is a one-shot reorganisation, not a
-- storage guarantee, and the table costs one extra heap fetch per index lookup.
ALTER TABLE retail.order_lines CLUSTER ON pk_order_lines;
CLUSTER retail.order_lines;

-- 2. Synonym (CREATE SYNONYM current_orders FOR orders).
--
-- PostgreSQL has no synonyms. A simple updatable view over the single base
-- table is the closest match: same column list, and INSERT, UPDATE and DELETE
-- pass through automatically. Reports outside this schema keep working if the
-- view is on their search_path. Grants are separate objects and must be
-- reapplied.
CREATE OR REPLACE VIEW retail.current_orders AS
SELECT * FROM retail.orders;

COMMENT ON VIEW retail.current_orders IS
    'Replaces Oracle synonym CURRENT_ORDERS. Simple updatable view over retail.orders';

-- 3. Materialized view.
--
-- Oracle BUILD IMMEDIATE REFRESH COMPLETE ON DEMAND maps almost exactly onto a
-- PostgreSQL materialized view populated at creation and refreshed by
-- REFRESH MATERIALIZED VIEW. The (+) join becomes a LEFT JOIN. A unique index
-- is added so REFRESH ... CONCURRENTLY is available, which Oracle did not need.
CREATE MATERIALIZED VIEW retail.mv_customer_order_rollup AS
SELECT
    c.customer_id,
    c.customer_code,
    COUNT(o.order_id) AS order_count,
    COALESCE(SUM(o.total_amount), 0) AS order_total,
    MAX(o.ordered_at) AS last_ordered_at
FROM retail.customers c
LEFT JOIN retail.orders o ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.customer_code
WITH DATA;

CREATE UNIQUE INDEX ux_mv_customer_rollup_customer
    ON retail.mv_customer_order_rollup (customer_id);
CREATE INDEX ix_mv_customer_rollup_total
    ON retail.mv_customer_order_rollup (order_total);

COMMENT ON MATERIALIZED VIEW retail.mv_customer_order_rollup IS
    'Synthetic refresh-on-demand summary used by legacy billing screens';

CREATE OR REPLACE FUNCTION retail.refresh_customer_order_rollup(p_concurrently boolean DEFAULT false)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_concurrently THEN
        REFRESH MATERIALIZED VIEW CONCURRENTLY retail.mv_customer_order_rollup;
    ELSE
        REFRESH MATERIALIZED VIEW retail.mv_customer_order_rollup;
    END IF;
END;
$$;

-- 4. Global temporary table (gtt_order_totals, ON COMMIT DELETE ROWS).
--
-- Oracle GTTs are permanent definitions with session-private contents.
-- PostgreSQL temp tables are session-private definitions, so the shape is kept
-- as a permanent, always-empty template table and each session materialises its
-- own temp table from it. ON COMMIT DELETE ROWS exists in PostgreSQL and is
-- used, so the row lifetime matches. Difference worth knowing: the temp table
-- is created on first use in a session, which costs one catalog write.
CREATE TABLE retail.gtt_order_totals_template (
    order_id            bigint,
    line_count          numeric,
    calculated_total    numeric(14, 2),
    loaded_at           timestamp(0) DEFAULT retail.sysdate()
);

COMMENT ON TABLE retail.gtt_order_totals_template IS
    'Shape only, stays empty. Session copies are created by retail.ensure_gtt_order_totals()';

CREATE OR REPLACE FUNCTION retail.ensure_gtt_order_totals()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF to_regclass('pg_temp.gtt_order_totals') IS NULL THEN
        CREATE TEMPORARY TABLE gtt_order_totals
            (LIKE retail.gtt_order_totals_template INCLUDING DEFAULTS)
            ON COMMIT DELETE ROWS;
    END IF;
END;
$$;

COMMENT ON FUNCTION retail.ensure_gtt_order_totals() IS
    'Creates the session-private stand-in for Oracle GLOBAL TEMPORARY TABLE gtt_order_totals';
