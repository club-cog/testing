-- Deterministic synthetic seed data, part 3.
--
-- The seed rows use explicit keys, so every sequence has to be pushed past the
-- highest seeded value. Oracle needed the same step after a data load, usually
-- by dropping and recreating the sequence. setval is the direct equivalent and
-- is idempotent when re-run.

SELECT setval('retail.seq_customers',     GREATEST((SELECT MAX(customer_id) FROM retail.customers), 1000));
SELECT setval('retail.seq_addresses',     GREATEST((SELECT MAX(address_id) FROM retail.addresses), 2000));
SELECT setval('retail.seq_products',      GREATEST((SELECT MAX(product_id) FROM retail.products), 3000));
SELECT setval('retail.seq_price_tiers',   GREATEST((SELECT MAX(tier_id) FROM retail.price_tiers), 4000));
SELECT setval('retail.seq_orders',        GREATEST((SELECT MAX(order_id) FROM retail.orders), 5000));
SELECT setval('retail.seq_invoices',      GREATEST((SELECT MAX(invoice_id) FROM retail.invoices), 6000));
SELECT setval('retail.seq_invoice_lines', GREATEST((SELECT MAX(invoice_line_id) FROM retail.invoice_lines), 7000));
SELECT setval('retail.seq_payments',      GREATEST((SELECT MAX(payment_id) FROM retail.payments), 8000));
SELECT setval('retail.seq_audit_log',     GREATEST((SELECT MAX(audit_id) FROM retail.audit_log), 9000));

-- The materialized view was built before the seed rows existed, so it is empty
-- until refreshed. Same operational fact as Oracle REFRESH COMPLETE ON DEMAND.
SELECT retail.refresh_customer_order_rollup();

ANALYZE retail.customers;
ANALYZE retail.orders;
ANALYZE retail.order_lines;
ANALYZE retail.invoices;
ANALYZE retail.payments;
