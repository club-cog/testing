-- The fixture rows use explicit primary keys in the 90000..99999 band. The
-- estate sequences start well below that band, so without this step a
-- sequence-generated key would eventually collide with a fixture key.
--
-- Oracle 18c and later support RESTART START WITH. On 12c, drop and recreate the
-- sequence instead.

ALTER SEQUENCE seq_customers     RESTART START WITH 100001;
ALTER SEQUENCE seq_addresses     RESTART START WITH 100001;
ALTER SEQUENCE seq_products      RESTART START WITH 100001;
ALTER SEQUENCE seq_price_tiers   RESTART START WITH 100001;
ALTER SEQUENCE seq_orders        RESTART START WITH 100001;
ALTER SEQUENCE seq_invoices      RESTART START WITH 100001;
ALTER SEQUENCE seq_invoice_lines RESTART START WITH 100001;
ALTER SEQUENCE seq_payments      RESTART START WITH 100001;
ALTER SEQUENCE seq_audit_log     RESTART START WITH 100001;

-- PostgreSQL equivalent:
--   ALTER SEQUENCE seq_customers RESTART WITH 100001;
-- and so on. If the converted schema uses identity columns instead of
-- sequences, the statement becomes
--   ALTER TABLE customers ALTER COLUMN customer_id RESTART WITH 100001;
