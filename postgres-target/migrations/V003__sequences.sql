-- V003: sequences.
--
-- The source estate assigns keys from named sequences inside BEFORE INSERT
-- triggers, and application code refers to the sequence names as strings
-- (see oracle-legacy-estate/app/raw_queries.sql). Identity columns would have
-- hidden those names, so named sequences are kept and owned by their column.
-- Oracle NOCACHE maps to CACHE 1.

CREATE SEQUENCE retail.seq_customers     START WITH 1001 INCREMENT BY 1 CACHE 1;
CREATE SEQUENCE retail.seq_addresses     START WITH 2001 INCREMENT BY 1 CACHE 1;
CREATE SEQUENCE retail.seq_products      START WITH 3001 INCREMENT BY 1 CACHE 1;
CREATE SEQUENCE retail.seq_price_tiers   START WITH 4001 INCREMENT BY 1 CACHE 1;
CREATE SEQUENCE retail.seq_orders        START WITH 5001 INCREMENT BY 1 CACHE 1;
CREATE SEQUENCE retail.seq_invoices      START WITH 6001 INCREMENT BY 1 CACHE 1;
CREATE SEQUENCE retail.seq_invoice_lines START WITH 7001 INCREMENT BY 1 CACHE 1;
CREATE SEQUENCE retail.seq_payments      START WITH 8001 INCREMENT BY 1 CACHE 1;
CREATE SEQUENCE retail.seq_audit_log     START WITH 9001 INCREMENT BY 1 CACHE 1;

ALTER SEQUENCE retail.seq_customers     OWNED BY retail.customers.customer_id;
ALTER SEQUENCE retail.seq_addresses     OWNED BY retail.addresses.address_id;
ALTER SEQUENCE retail.seq_products      OWNED BY retail.products.product_id;
ALTER SEQUENCE retail.seq_price_tiers   OWNED BY retail.price_tiers.tier_id;
ALTER SEQUENCE retail.seq_orders        OWNED BY retail.orders.order_id;
ALTER SEQUENCE retail.seq_invoices      OWNED BY retail.invoices.invoice_id;
ALTER SEQUENCE retail.seq_invoice_lines OWNED BY retail.invoice_lines.invoice_line_id;
ALTER SEQUENCE retail.seq_payments      OWNED BY retail.payments.payment_id;
ALTER SEQUENCE retail.seq_audit_log     OWNED BY retail.audit_log.audit_id;

-- Column defaults are added for the tables whose Oracle triggers only assign a
-- key when the caller left it NULL. The triggers in V007 still run, so an
-- explicit caller-supplied key keeps winning, exactly as in Oracle.
ALTER TABLE retail.invoice_lines
    ALTER COLUMN invoice_line_id SET DEFAULT nextval('retail.seq_invoice_lines');
ALTER TABLE retail.payments
    ALTER COLUMN payment_id SET DEFAULT nextval('retail.seq_payments');
ALTER TABLE retail.price_tiers
    ALTER COLUMN tier_id SET DEFAULT nextval('retail.seq_price_tiers');
