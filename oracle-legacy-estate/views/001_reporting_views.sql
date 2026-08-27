CREATE OR REPLACE VIEW v_order_summary AS
SELECT
    o.order_id,
    o.order_number,
    o.customer_id,
    c.customer_code,
    c.display_name,
    o.order_status,
    o.ordered_at,
    o.subtotal_amount,
    o.discount_amount,
    o.tax_amount,
    o.total_amount,
    NVL(i.invoice_status, 'UNBILLED') AS invoice_status,
    NVL(i.invoice_total, 0) AS invoice_total
FROM orders o, customers c, invoices i
WHERE o.customer_id = c.customer_id
  AND o.order_id = i.order_id(+);

CREATE OR REPLACE VIEW v_customer_balance AS
SELECT
    c.customer_id,
    c.customer_code,
    c.display_name,
    NVL(SUM(i.invoice_total), 0) AS invoiced_total,
    NVL(SUM(p.amount_paid), 0) AS paid_total,
    NVL(SUM(i.invoice_total), 0) - NVL(SUM(p.amount_paid), 0) AS balance_due
FROM customers c, orders o, invoices i, payments p
WHERE c.customer_id = o.customer_id(+)
  AND o.order_id = i.order_id(+)
  AND i.invoice_id = p.invoice_id(+)
GROUP BY c.customer_id, c.customer_code, c.display_name;

CREATE OR REPLACE VIEW v_recent_orders AS
SELECT order_id, order_number, customer_id, order_status, ordered_at, total_amount
FROM (
    SELECT o.order_id,
           o.order_number,
           o.customer_id,
           o.order_status,
           o.ordered_at,
           o.total_amount
    FROM orders o
    ORDER BY o.ordered_at DESC
)
WHERE ROWNUM <= 50;
