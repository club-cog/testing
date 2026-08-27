-- Sequence names are intentionally terse because application code refers to
-- them as strings in more than one place.

CREATE SEQUENCE seq_customers START WITH 1001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_addresses START WITH 2001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_products START WITH 3001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_price_tiers START WITH 4001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_orders START WITH 5001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_invoices START WITH 6001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_invoice_lines START WITH 7001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_payments START WITH 8001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_audit_log START WITH 9001 INCREMENT BY 1 NOCACHE;

CREATE INDEX ix_customers_parent ON customers (parent_customer_id);
CREATE INDEX ix_addresses_customer_kind ON addresses (customer_id, address_kind);
CREATE INDEX ix_products_group_active ON products (product_group, active_flag);
CREATE INDEX ix_price_tiers_product_qty ON price_tiers (product_id, minimum_quantity);
CREATE INDEX ix_orders_customer_date ON orders (customer_id, ordered_at DESC);
CREATE INDEX ix_orders_status_date ON orders (order_status, ordered_at DESC);
CREATE INDEX ix_order_lines_product ON order_lines (product_id);
CREATE INDEX ix_invoices_status_due ON invoices (invoice_status, due_on);
CREATE INDEX ix_payments_invoice_date ON payments (invoice_id, paid_on);
CREATE INDEX ix_audit_entity_time ON audit_log (entity_name, entity_id, event_time);

CREATE BITMAP INDEX bix_orders_status ON orders (order_status);

CREATE UNIQUE INDEX ux_invoice_lines_invoice_line
    ON invoice_lines (invoice_id, order_line_number);
