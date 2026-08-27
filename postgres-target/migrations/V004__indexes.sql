-- V004: indexes.
--
-- Straight carry over for the b-tree indexes. Oracle DESC index columns are
-- kept as DESC because PostgreSQL can scan either direction but the ordered
-- pagination queries read better with the declared order preserved.

CREATE INDEX ix_customers_parent ON retail.customers (parent_customer_id);
CREATE INDEX ix_addresses_customer_kind ON retail.addresses (customer_id, address_kind);
CREATE INDEX ix_products_group_active ON retail.products (product_group, active_flag);
CREATE INDEX ix_price_tiers_product_qty ON retail.price_tiers (product_id, minimum_quantity);
CREATE INDEX ix_orders_customer_date ON retail.orders (customer_id, ordered_at DESC);
CREATE INDEX ix_orders_status_date ON retail.orders (order_status, ordered_at DESC);
CREATE INDEX ix_order_lines_product ON retail.order_lines (product_id);
CREATE INDEX ix_invoices_status_due ON retail.invoices (invoice_status, due_on);
CREATE INDEX ix_payments_invoice_date ON retail.payments (invoice_id, paid_on);
CREATE INDEX ix_audit_entity_time ON retail.audit_log (entity_name, entity_id, event_time);

CREATE UNIQUE INDEX ux_invoice_lines_invoice_line
    ON retail.invoice_lines (invoice_id, order_line_number);

-- Oracle: CREATE BITMAP INDEX bix_orders_status ON orders (order_status).
--
-- PostgreSQL has no persistent bitmap index; it builds bitmaps at run time from
-- b-tree scans. Replacement is a plain b-tree on the same column, plus a
-- partial index for the selective lookup the batch actually runs (open work).
-- A DBA who wants the storage profile of a bitmap index should compare this
-- against BRIN on ordered data before sign off.
CREATE INDEX bix_orders_status ON retail.orders (order_status);
CREATE INDEX ix_orders_status_open ON retail.orders (ordered_at DESC)
    WHERE order_status IN ('OPEN', 'HELD');
