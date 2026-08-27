-- Converted application-side SQL. raw_queries.sql is left unchanged next to it.
--
-- Treatment per statement:
--   1. hint dropped, comma join plus (+) became explicit joins, NVL -> COALESCE
--   2. ROWNUM -> LIMIT, and the NVL(:status, status) idiom made explicit
--   3. CONNECT BY -> the converted function pkg_customer_hier.print_tree
--   4. :end_date + 1 -> :end_date + interval '1 day'
--   5. DUAL dropped; PostgreSQL selects an expression with no table

-- 1
SELECT o.order_id,
       o.order_number,
       c.customer_code,
       COALESCE(i.invoice_status, 'UNBILLED') AS invoice_status,
       COALESCE(i.invoice_total, 0) AS invoice_total
FROM retail.orders o
JOIN retail.customers c ON o.customer_id = c.customer_id
LEFT JOIN retail.invoices i ON o.order_id = i.order_id
WHERE o.order_status <> 'VOID'
ORDER BY o.ordered_at DESC, o.order_id DESC;

-- 2
-- WHERE status = NVL(:status, status) matched every non-null status when the
-- bind was null. Written out, that is "no filter when the bind is null".
SELECT customer_id, customer_code, display_name
FROM retail.customers
WHERE (%(status)s IS NULL OR status = %(status)s)
LIMIT COALESCE(%(max_rows)s, 100);

-- 3
SELECT customer_id, customer_code
FROM pkg_customer_hier.print_tree(%(root_customer_id)s);

-- 4
-- Oracle DATE arithmetic added one day to a bare number. The interval says so.
SELECT order_id, order_number, total_amount
FROM retail.orders
WHERE ordered_at BETWEEN %(start_date)s AND %(end_date)s + interval '1 day'
  AND total_amount > COALESCE(%(minimum_total)s, 0);

-- 5
SELECT 'ORD-' || nextval('retail.seq_orders')::text AS proposed_order_number;
