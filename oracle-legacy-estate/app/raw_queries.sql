-- Application-side SQL references gathered from an invented batch worker.

SELECT /*+ FIRST_ROWS(50) */
       o.order_id,
       o.order_number,
       c.customer_code,
       NVL(i.invoice_status, 'UNBILLED') AS invoice_status,
       NVL(i.invoice_total, 0) AS invoice_total
FROM orders o, customers c, invoices i
WHERE o.customer_id = c.customer_id
  AND o.order_id = i.order_id(+)
  AND o.order_status <> 'VOID'
ORDER BY o.ordered_at DESC;

SELECT customer_id, customer_code, display_name
FROM customers
WHERE status = NVL(:status, status)
  AND ROWNUM <= NVL(:max_rows, 100);

SELECT customer_id, customer_code
FROM customers
WHERE customer_id IN (
    SELECT customer_id
    FROM customers
    START WITH customer_id = :root_customer_id
    CONNECT BY PRIOR customer_id = parent_customer_id
);

SELECT order_id, order_number, total_amount
FROM orders
WHERE ordered_at BETWEEN :start_date AND :end_date + 1
  AND total_amount > NVL(:minimum_total, 0);

SELECT 'ORD-' || seq_orders.NEXTVAL AS proposed_order_number
FROM DUAL;
