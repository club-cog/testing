-- Objects below are read by the old reporting routines.

CREATE SYNONYM current_orders FOR orders;

CREATE MATERIALIZED VIEW mv_customer_order_rollup
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS
SELECT
    c.customer_id,
    c.customer_code,
    COUNT(o.order_id) AS order_count,
    NVL(SUM(o.total_amount), 0) AS order_total,
    MAX(o.ordered_at) AS last_ordered_at
FROM customers c, orders o
WHERE c.customer_id = o.customer_id(+)
GROUP BY c.customer_id, c.customer_code;

CREATE INDEX ix_mv_customer_rollup_total
    ON mv_customer_order_rollup (order_total);

COMMENT ON MATERIALIZED VIEW mv_customer_order_rollup IS
    'Synthetic refresh-on-demand summary used by legacy billing screens';
