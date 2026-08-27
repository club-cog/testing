-- V005: reporting views.
--
-- Oracle (+) outer join syntax becomes explicit LEFT JOIN. NVL becomes COALESCE.

CREATE OR REPLACE VIEW retail.v_order_summary AS
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
    COALESCE(i.invoice_status, 'UNBILLED') AS invoice_status,
    COALESCE(i.invoice_total, 0) AS invoice_total
FROM retail.orders o
JOIN retail.customers c ON o.customer_id = c.customer_id
LEFT JOIN retail.invoices i ON o.order_id = i.order_id;

-- Faithful conversion of the Oracle view, including a defect.
--
-- The source chains three (+) joins customers -> orders -> invoices -> payments
-- and then sums invoice_total. When an invoice has more than one captured
-- payment the join fans out and invoice_total is counted once per payment row,
-- so invoiced_total and balance_due are inflated. That behaviour is reproduced
-- here on purpose: reports built on the Oracle view match this output. See
-- v_customer_balance_deduped for the corrected shape, and CONVERSION-NOTES.md
-- for the sign off this needs.
CREATE OR REPLACE VIEW retail.v_customer_balance AS
SELECT
    c.customer_id,
    c.customer_code,
    c.display_name,
    COALESCE(SUM(i.invoice_total), 0) AS invoiced_total,
    COALESCE(SUM(p.amount_paid), 0) AS paid_total,
    COALESCE(SUM(i.invoice_total), 0) - COALESCE(SUM(p.amount_paid), 0) AS balance_due
FROM retail.customers c
LEFT JOIN retail.orders o ON c.customer_id = o.customer_id
LEFT JOIN retail.invoices i ON o.order_id = i.order_id
LEFT JOIN retail.payments p ON i.invoice_id = p.invoice_id
GROUP BY c.customer_id, c.customer_code, c.display_name;

COMMENT ON VIEW retail.v_customer_balance IS
    'Faithful port including the Oracle join fan-out: invoice_total repeats per payment row';

-- Deliberately different, offered alongside the faithful view. Not wired into
-- anything yet; a DBA and the report owner decide whether to switch.
CREATE OR REPLACE VIEW retail.v_customer_balance_deduped AS
WITH invoice_rollup AS (
    SELECT
        o.customer_id,
        i.invoice_id,
        i.invoice_total,
        (SELECT COALESCE(SUM(p.amount_paid), 0)
         FROM retail.payments p
         WHERE p.invoice_id = i.invoice_id) AS paid_total
    FROM retail.orders o
    JOIN retail.invoices i ON o.order_id = i.order_id
)
SELECT
    c.customer_id,
    c.customer_code,
    c.display_name,
    COALESCE(SUM(r.invoice_total), 0) AS invoiced_total,
    COALESCE(SUM(r.paid_total), 0) AS paid_total,
    COALESCE(SUM(r.invoice_total), 0) - COALESCE(SUM(r.paid_total), 0) AS balance_due
FROM retail.customers c
LEFT JOIN invoice_rollup r ON r.customer_id = c.customer_id
GROUP BY c.customer_id, c.customer_code, c.display_name;

-- Oracle used an inline view with ORDER BY plus ROWNUM <= 50. The ordering was
-- applied before the row limit only because of the nested subquery, which is
-- fragile in Oracle too. LIMIT states the intent directly. order_id is added as
-- a tie breaker so repeated runs return the same 50 rows; Oracle did not
-- guarantee that when ordered_at ties.
CREATE OR REPLACE VIEW retail.v_recent_orders AS
SELECT order_id, order_number, customer_id, order_status, ordered_at, total_amount
FROM retail.orders
ORDER BY ordered_at DESC, order_id DESC
LIMIT 50;
