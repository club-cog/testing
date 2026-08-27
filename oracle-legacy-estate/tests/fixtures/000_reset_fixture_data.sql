-- Fixture reset for the Oracle characterization suite.
-- Synthetic data only. Every identifier and value below was invented for the
-- migration demo fixture.
--
-- All fixture primary keys live in the 90000..99999 band so that they never
-- collide with sequence-generated keys. Delete order follows the foreign keys.
--
-- Portability: plain DELETE statements, valid on Oracle and PostgreSQL.

DELETE FROM audit_log WHERE audit_id BETWEEN 90000 AND 99999;
DELETE FROM payments WHERE payment_id BETWEEN 90000 AND 99999;
DELETE FROM invoice_lines WHERE invoice_line_id BETWEEN 90000 AND 99999;
DELETE FROM invoices WHERE invoice_id BETWEEN 90000 AND 99999;
DELETE FROM order_lines WHERE order_id BETWEEN 90000 AND 99999;
DELETE FROM orders WHERE order_id BETWEEN 90000 AND 99999;
DELETE FROM price_tiers WHERE tier_id BETWEEN 90000 AND 99999;
DELETE FROM products WHERE product_id BETWEEN 90000 AND 99999;
DELETE FROM addresses WHERE address_id BETWEEN 90000 AND 99999;

-- Customers are self-referencing, so break the parent links before deleting.
UPDATE customers SET parent_customer_id = NULL
WHERE customer_id BETWEEN 90000 AND 99999;

DELETE FROM customers WHERE customer_id BETWEEN 90000 AND 99999;

-- Rows a test run generated. The sequences are restarted at 100001 by
-- 060_align_sequences.sql, so every key at or above 100000 came from a test,
-- including the audit rows that write_billing_log committed autonomously.
-- Run this against a schema dedicated to the test estate, not against a shared
-- one, because these predicates do not distinguish other callers.
DELETE FROM audit_log WHERE audit_id >= 100000;
DELETE FROM payments WHERE payment_id >= 100000;
DELETE FROM invoice_lines WHERE invoice_line_id >= 100000;
DELETE FROM invoices WHERE invoice_id >= 100000;
DELETE FROM order_lines WHERE order_id >= 100000;
DELETE FROM orders WHERE order_id >= 100000;
DELETE FROM price_tiers WHERE tier_id >= 100000;
DELETE FROM products WHERE product_id >= 100000;
DELETE FROM addresses WHERE address_id >= 100000;

UPDATE customers SET parent_customer_id = NULL WHERE customer_id >= 100000;
DELETE FROM customers WHERE customer_id >= 100000;

COMMIT;
