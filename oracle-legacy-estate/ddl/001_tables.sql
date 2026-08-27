-- Synthetic Oracle 19c-style estate. This file is a migration fixture only.
-- The names and values are invented for a retail-orders demo.

CREATE TABLE customers (
    customer_id          NUMBER,
    customer_code        VARCHAR2(24 CHAR) CONSTRAINT nn_customers_code NOT NULL,
    display_name         VARCHAR2(160 BYTE) CONSTRAINT nn_customers_name NOT NULL,
    status               VARCHAR2(1 BYTE) DEFAULT 'A'
        CONSTRAINT ck_customers_status CHECK (status IN ('A', 'I', 'H')),
    preferred_channel     VARCHAR2(12 CHAR) DEFAULT ''
        CONSTRAINT ck_customers_channel CHECK (preferred_channel <> ''),
    credit_limit         NUMBER(12, 2),
    joined_on             DATE DEFAULT SYSDATE,
    last_contacted_on     DATE,
    parent_customer_id   NUMBER,
    profile_note         CLOB,
    avatar_blob          BLOB,
    external_ref         RAW(16),
    CONSTRAINT pk_customers PRIMARY KEY (customer_id),
    CONSTRAINT uk_customers_code UNIQUE (customer_code),
    CONSTRAINT fk_customers_parent FOREIGN KEY (parent_customer_id)
        REFERENCES customers (customer_id),
    CONSTRAINT ck_customers_limit CHECK (credit_limit IS NULL OR credit_limit >= 0)
);

COMMENT ON TABLE customers IS 'Synthetic account records for the retail order fixture';
COMMENT ON COLUMN customers.preferred_channel IS
    'Legacy optional value; Oracle treats an empty string as NULL';

CREATE TABLE addresses (
    address_id          NUMBER,
    customer_id         NUMBER NOT NULL,
    address_kind        VARCHAR2(10 CHAR) DEFAULT 'SHIP',
    line_one            VARCHAR2(120 BYTE) NOT NULL,
    line_two            VARCHAR2(120 BYTE),
    city_name           VARCHAR2(80 CHAR) NOT NULL,
    region_code         VARCHAR2(12 BYTE),
    postal_code         VARCHAR2(16 CHAR),
    country_code        VARCHAR2(2 BYTE) DEFAULT 'ZZ',
    validated_flag      VARCHAR2(1 BYTE) DEFAULT ''
        CONSTRAINT ck_addresses_valid CHECK (validated_flag <> ''),
    created_at          DATE DEFAULT SYSDATE,
    CONSTRAINT pk_addresses PRIMARY KEY (address_id),
    CONSTRAINT fk_addresses_customer FOREIGN KEY (customer_id)
        REFERENCES customers (customer_id),
    CONSTRAINT ck_addresses_kind CHECK (address_kind IN ('BILL', 'SHIP', 'OTHER'))
);

CREATE TABLE products (
    product_id          NUMBER,
    sku                 VARCHAR2(30 BYTE) NOT NULL,
    product_name        VARCHAR2(140 CHAR) NOT NULL,
    product_group       VARCHAR2(40 CHAR),
    active_flag         VARCHAR2(1 BYTE) DEFAULT 'Y'
        CONSTRAINT ck_products_active CHECK (active_flag IN ('Y', 'N')),
    base_price          NUMBER(10, 2) NOT NULL,
    weight_kg           NUMBER,
    description         CLOB,
    image_blob          BLOB,
    created_on          DATE DEFAULT SYSDATE,
    retired_on          DATE,
    CONSTRAINT pk_products PRIMARY KEY (product_id),
    CONSTRAINT uk_products_sku UNIQUE (sku),
    CONSTRAINT ck_products_price CHECK (base_price >= 0)
);

CREATE TABLE price_tiers (
    tier_id             NUMBER,
    product_id          NUMBER NOT NULL,
    tier_code           VARCHAR2(12 CHAR) NOT NULL,
    minimum_quantity    NUMBER DEFAULT 1,
    unit_price          NUMBER(10, 2) NOT NULL,
    valid_from          DATE DEFAULT SYSDATE,
    valid_to            DATE,
    tier_note           VARCHAR2(240 BYTE),
    CONSTRAINT pk_price_tiers PRIMARY KEY (tier_id),
    CONSTRAINT fk_price_tiers_product FOREIGN KEY (product_id)
        REFERENCES products (product_id),
    CONSTRAINT uk_price_tiers_product UNIQUE (product_id, tier_code),
    CONSTRAINT ck_price_tiers_quantity CHECK (minimum_quantity > 0),
    CONSTRAINT ck_price_tiers_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE orders (
    order_id            NUMBER,
    order_number        VARCHAR2(28 BYTE) NOT NULL,
    customer_id         NUMBER NOT NULL,
    bill_address_id     NUMBER,
    ship_address_id     NUMBER,
    order_status        VARCHAR2(16 CHAR) DEFAULT 'OPEN' NOT NULL,
    ordered_at          DATE DEFAULT SYSDATE,
    requested_by        VARCHAR2(80 BYTE),
    currency_code       VARCHAR2(3 BYTE) DEFAULT 'ZZ',
    subtotal_amount     NUMBER(14, 2) DEFAULT 0,
    discount_amount     NUMBER(14, 2) DEFAULT 0,
    tax_amount          NUMBER(14, 2) DEFAULT 0,
    total_amount        NUMBER(14, 2) DEFAULT 0,
    note_text           CLOB,
    source_token        RAW(16),
    CONSTRAINT pk_orders PRIMARY KEY (order_id),
    CONSTRAINT uk_orders_number UNIQUE (order_number),
    CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id)
        REFERENCES customers (customer_id),
    CONSTRAINT fk_orders_bill_address FOREIGN KEY (bill_address_id)
        REFERENCES addresses (address_id),
    CONSTRAINT fk_orders_ship_address FOREIGN KEY (ship_address_id)
        REFERENCES addresses (address_id),
    CONSTRAINT ck_orders_status CHECK (
        order_status IN ('OPEN', 'HELD', 'READY', 'CLOSED', 'VOID')
    ),
    CONSTRAINT ck_orders_total CHECK (total_amount >= 0)
);

-- The legacy line table is index-organized to make a rowid-based migration
-- assumption visible to the next engineer.
CREATE TABLE order_lines (
    order_id            NUMBER NOT NULL,
    line_number         NUMBER NOT NULL,
    product_id          NUMBER NOT NULL,
    quantity            NUMBER DEFAULT 1 NOT NULL,
    unit_price          NUMBER(10, 2) NOT NULL,
    discount_rate       NUMBER(5, 2) DEFAULT 0,
    extended_amount     NUMBER(14, 2),
    line_note           VARCHAR2(240 CHAR),
    CONSTRAINT pk_order_lines PRIMARY KEY (order_id, line_number),
    CONSTRAINT fk_order_lines_order FOREIGN KEY (order_id)
        REFERENCES orders (order_id),
    CONSTRAINT fk_order_lines_product FOREIGN KEY (product_id)
        REFERENCES products (product_id),
    CONSTRAINT ck_order_lines_qty CHECK (quantity > 0),
    CONSTRAINT ck_order_lines_discount CHECK (discount_rate BETWEEN 0 AND 100)
)
ORGANIZATION INDEX
INCLUDING quantity
OVERFLOW;

CREATE TABLE invoices (
    invoice_id          NUMBER,
    invoice_number      VARCHAR2(28 BYTE) NOT NULL,
    order_id            NUMBER NOT NULL,
    issued_on           DATE DEFAULT SYSDATE,
    due_on              DATE,
    invoice_status      VARCHAR2(14 CHAR) DEFAULT 'DRAFT',
    invoice_total       NUMBER(14, 2) DEFAULT 0,
    tax_total           NUMBER(14, 2) DEFAULT 0,
    rendered_pdf        BLOB,
    delivery_note       CLOB,
    CONSTRAINT pk_invoices PRIMARY KEY (invoice_id),
    CONSTRAINT uk_invoices_number UNIQUE (invoice_number),
    CONSTRAINT uk_invoices_order UNIQUE (order_id),
    CONSTRAINT fk_invoices_order FOREIGN KEY (order_id)
        REFERENCES orders (order_id),
    CONSTRAINT ck_invoices_status CHECK (
        invoice_status IN ('DRAFT', 'ISSUED', 'PARTIAL', 'PAID', 'VOID')
    )
);

CREATE TABLE invoice_lines (
    invoice_line_id     NUMBER,
    invoice_id          NUMBER NOT NULL,
    order_line_number   NUMBER NOT NULL,
    line_text           VARCHAR2(180 CHAR),
    quantity            NUMBER(9, 0),
    line_amount         NUMBER(14, 2),
    tax_amount          NUMBER(14, 2),
    CONSTRAINT pk_invoice_lines PRIMARY KEY (invoice_line_id),
    CONSTRAINT fk_invoice_lines_invoice FOREIGN KEY (invoice_id)
        REFERENCES invoices (invoice_id),
    CONSTRAINT ck_invoice_lines_qty CHECK (quantity > 0)
);

CREATE TABLE payments (
    payment_id          NUMBER,
    invoice_id          NUMBER NOT NULL,
    paid_on             DATE DEFAULT SYSDATE,
    payment_method      VARCHAR2(14 BYTE),
    payment_status      VARCHAR2(12 CHAR) DEFAULT 'CAPTURED',
    amount_paid         NUMBER(14, 2) NOT NULL,
    confirmation_code   RAW(16),
    gateway_note        CLOB,
    CONSTRAINT pk_payments PRIMARY KEY (payment_id),
    CONSTRAINT fk_payments_invoice FOREIGN KEY (invoice_id)
        REFERENCES invoices (invoice_id),
    CONSTRAINT ck_payments_status CHECK (
        payment_status IN ('CAPTURED', 'PENDING', 'REVERSED')
    ),
    CONSTRAINT ck_payments_amount CHECK (amount_paid > 0)
);

CREATE TABLE audit_log (
    audit_id            NUMBER,
    event_time          DATE DEFAULT SYSDATE,
    entity_name         VARCHAR2(40 BYTE) NOT NULL,
    entity_id           NUMBER,
    action_code         VARCHAR2(20 CHAR) NOT NULL,
    actor_name          VARCHAR2(80 BYTE),
    payload             CLOB,
    event_fingerprint   RAW(16),
    CONSTRAINT pk_audit_log PRIMARY KEY (audit_id)
);

CREATE GLOBAL TEMPORARY TABLE gtt_order_totals (
    order_id            NUMBER,
    line_count          NUMBER,
    calculated_total    NUMBER(14, 2),
    loaded_at           DATE DEFAULT SYSDATE
) ON COMMIT DELETE ROWS;
