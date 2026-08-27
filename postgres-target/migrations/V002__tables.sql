-- V002: tables.
--
-- Type mapping decisions (full rationale in postgres-target/CONVERSION-NOTES.md):
--
--   NUMBER (no precision) surrogate key  -> bigint       (keys are integral, index-friendly)
--   NUMBER (no precision) quantity/count -> numeric      (unconstrained scale preserved)
--   NUMBER(p,s)                          -> numeric(p,s) (exact carry over)
--   NUMBER(9,0)                          -> integer      (fits, cheaper than numeric)
--   VARCHAR2(n CHAR)                     -> varchar(n)   (PostgreSQL counts characters)
--   VARCHAR2(n BYTE)                     -> varchar(n) plus octet_length CHECK where the
--                                           byte limit is load bearing
--   DATE                                 -> timestamp(0) without time zone
--   CLOB                                 -> text
--   BLOB                                 -> bytea
--   RAW(16)                              -> bytea with an octet_length = 16 CHECK

CREATE TABLE retail.customers (
    customer_id          bigint NOT NULL,
    customer_code        varchar(24) CONSTRAINT nn_customers_code NOT NULL,
    display_name         varchar(160) CONSTRAINT nn_customers_name NOT NULL,
    status               varchar(1) DEFAULT 'A',
    preferred_channel    varchar(12) DEFAULT NULL,
    credit_limit         numeric(12, 2),
    joined_on            timestamp(0) DEFAULT retail.sysdate(),
    last_contacted_on    timestamp(0),
    parent_customer_id   bigint,
    profile_note         text,
    avatar_blob          bytea,
    external_ref         bytea,
    CONSTRAINT pk_customers PRIMARY KEY (customer_id),
    CONSTRAINT uk_customers_code UNIQUE (customer_code),
    CONSTRAINT fk_customers_parent FOREIGN KEY (parent_customer_id)
        REFERENCES retail.customers (customer_id),
    CONSTRAINT ck_customers_status CHECK (status IN ('A', 'I', 'H')),
    CONSTRAINT ck_customers_channel CHECK (preferred_channel <> ''),
    CONSTRAINT ck_customers_limit CHECK (credit_limit IS NULL OR credit_limit >= 0),
    -- VARCHAR2(160 BYTE) in the source. varchar(160) counts characters, so the
    -- byte ceiling is restated to keep multibyte input from growing past what
    -- Oracle accepted.
    CONSTRAINT ck_customers_name_bytes CHECK (octet_length(display_name) <= 160),
    CONSTRAINT ck_customers_external_ref CHECK (
        external_ref IS NULL OR octet_length(external_ref) = 16
    )
);

COMMENT ON TABLE retail.customers IS 'Synthetic account records for the retail order fixture';
COMMENT ON COLUMN retail.customers.preferred_channel IS
    'Legacy optional value. Oracle stored an empty string as NULL; trigger trg_customers_bi does the same here';

CREATE TABLE retail.addresses (
    address_id          bigint NOT NULL,
    customer_id         bigint NOT NULL,
    address_kind        varchar(10) DEFAULT 'SHIP',
    line_one            varchar(120) NOT NULL,
    line_two            varchar(120),
    city_name           varchar(80) NOT NULL,
    region_code         varchar(12),
    postal_code         varchar(16),
    country_code        varchar(2) DEFAULT 'ZZ',
    validated_flag      varchar(1) DEFAULT NULL,
    created_at          timestamp(0) DEFAULT retail.sysdate(),
    CONSTRAINT pk_addresses PRIMARY KEY (address_id),
    CONSTRAINT fk_addresses_customer FOREIGN KEY (customer_id)
        REFERENCES retail.customers (customer_id),
    CONSTRAINT ck_addresses_kind CHECK (address_kind IN ('BILL', 'SHIP', 'OTHER')),
    CONSTRAINT ck_addresses_valid CHECK (validated_flag <> ''),
    CONSTRAINT ck_addresses_line_one_bytes CHECK (octet_length(line_one) <= 120)
);

CREATE TABLE retail.products (
    product_id          bigint NOT NULL,
    sku                 varchar(30) NOT NULL,
    product_name        varchar(140) NOT NULL,
    product_group       varchar(40),
    active_flag         varchar(1) DEFAULT 'Y',
    base_price          numeric(10, 2) NOT NULL,
    weight_kg           numeric,
    description         text,
    image_blob          bytea,
    created_on          timestamp(0) DEFAULT retail.sysdate(),
    retired_on          timestamp(0),
    CONSTRAINT pk_products PRIMARY KEY (product_id),
    CONSTRAINT uk_products_sku UNIQUE (sku),
    CONSTRAINT ck_products_active CHECK (active_flag IN ('Y', 'N')),
    CONSTRAINT ck_products_price CHECK (base_price >= 0)
);

CREATE TABLE retail.price_tiers (
    tier_id             bigint NOT NULL,
    product_id          bigint NOT NULL,
    tier_code           varchar(12) NOT NULL,
    minimum_quantity    numeric DEFAULT 1,
    unit_price          numeric(10, 2) NOT NULL,
    valid_from          timestamp(0) DEFAULT retail.sysdate(),
    valid_to            timestamp(0),
    tier_note           varchar(240),
    CONSTRAINT pk_price_tiers PRIMARY KEY (tier_id),
    CONSTRAINT fk_price_tiers_product FOREIGN KEY (product_id)
        REFERENCES retail.products (product_id),
    CONSTRAINT uk_price_tiers_product UNIQUE (product_id, tier_code),
    CONSTRAINT ck_price_tiers_quantity CHECK (minimum_quantity > 0),
    CONSTRAINT ck_price_tiers_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE retail.orders (
    order_id            bigint NOT NULL,
    order_number        varchar(28) NOT NULL,
    customer_id         bigint NOT NULL,
    bill_address_id     bigint,
    ship_address_id     bigint,
    order_status        varchar(16) DEFAULT 'OPEN' NOT NULL,
    ordered_at          timestamp(0) DEFAULT retail.sysdate(),
    requested_by        varchar(80),
    currency_code       varchar(3) DEFAULT 'ZZ',
    subtotal_amount     numeric(14, 2) DEFAULT 0,
    discount_amount     numeric(14, 2) DEFAULT 0,
    tax_amount          numeric(14, 2) DEFAULT 0,
    total_amount        numeric(14, 2) DEFAULT 0,
    note_text           text,
    source_token        bytea,
    CONSTRAINT pk_orders PRIMARY KEY (order_id),
    CONSTRAINT uk_orders_number UNIQUE (order_number),
    CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id)
        REFERENCES retail.customers (customer_id),
    CONSTRAINT fk_orders_bill_address FOREIGN KEY (bill_address_id)
        REFERENCES retail.addresses (address_id),
    CONSTRAINT fk_orders_ship_address FOREIGN KEY (ship_address_id)
        REFERENCES retail.addresses (address_id),
    CONSTRAINT ck_orders_status CHECK (
        order_status IN ('OPEN', 'HELD', 'READY', 'CLOSED', 'VOID')
    ),
    CONSTRAINT ck_orders_total CHECK (total_amount >= 0),
    CONSTRAINT ck_orders_source_token CHECK (
        source_token IS NULL OR octet_length(source_token) = 16
    )
);

-- Source table was ORGANIZATION INDEX ... INCLUDING quantity OVERFLOW.
-- PostgreSQL has no index-organized storage. Closest sound design: an ordinary
-- heap table plus CLUSTER on the primary key index, which gives the same
-- physical ordering once, without Oracle's automatic maintenance. See
-- V006 for the CLUSTER marking and CONVERSION-NOTES.md for the trade-off.
CREATE TABLE retail.order_lines (
    order_id            bigint NOT NULL,
    line_number         numeric NOT NULL,
    product_id          bigint NOT NULL,
    quantity            numeric DEFAULT 1 NOT NULL,
    unit_price          numeric(10, 2) NOT NULL,
    discount_rate       numeric(5, 2) DEFAULT 0,
    extended_amount     numeric(14, 2),
    line_note           varchar(240),
    CONSTRAINT pk_order_lines PRIMARY KEY (order_id, line_number),
    CONSTRAINT fk_order_lines_order FOREIGN KEY (order_id)
        REFERENCES retail.orders (order_id),
    CONSTRAINT fk_order_lines_product FOREIGN KEY (product_id)
        REFERENCES retail.products (product_id),
    CONSTRAINT ck_order_lines_qty CHECK (quantity > 0),
    CONSTRAINT ck_order_lines_discount CHECK (discount_rate BETWEEN 0 AND 100)
);

CREATE TABLE retail.invoices (
    invoice_id          bigint NOT NULL,
    invoice_number      varchar(28) NOT NULL,
    order_id            bigint NOT NULL,
    issued_on           timestamp(0) DEFAULT retail.sysdate(),
    due_on              timestamp(0),
    invoice_status      varchar(14) DEFAULT 'DRAFT',
    invoice_total       numeric(14, 2) DEFAULT 0,
    tax_total           numeric(14, 2) DEFAULT 0,
    rendered_pdf        bytea,
    delivery_note       text,
    CONSTRAINT pk_invoices PRIMARY KEY (invoice_id),
    CONSTRAINT uk_invoices_number UNIQUE (invoice_number),
    CONSTRAINT uk_invoices_order UNIQUE (order_id),
    CONSTRAINT fk_invoices_order FOREIGN KEY (order_id)
        REFERENCES retail.orders (order_id),
    CONSTRAINT ck_invoices_status CHECK (
        invoice_status IN ('DRAFT', 'ISSUED', 'PARTIAL', 'PAID', 'VOID')
    )
);

CREATE TABLE retail.invoice_lines (
    invoice_line_id     bigint NOT NULL,
    invoice_id          bigint NOT NULL,
    order_line_number   numeric NOT NULL,
    line_text           varchar(180),
    -- NUMBER(9,0) has a maximum of 999999999, inside the integer range.
    quantity            integer,
    line_amount         numeric(14, 2),
    tax_amount          numeric(14, 2),
    CONSTRAINT pk_invoice_lines PRIMARY KEY (invoice_line_id),
    CONSTRAINT fk_invoice_lines_invoice FOREIGN KEY (invoice_id)
        REFERENCES retail.invoices (invoice_id),
    CONSTRAINT ck_invoice_lines_qty CHECK (quantity > 0)
);

CREATE TABLE retail.payments (
    payment_id          bigint NOT NULL,
    invoice_id          bigint NOT NULL,
    paid_on             timestamp(0) DEFAULT retail.sysdate(),
    payment_method      varchar(14),
    payment_status      varchar(12) DEFAULT 'CAPTURED',
    amount_paid         numeric(14, 2) NOT NULL,
    confirmation_code   bytea,
    gateway_note        text,
    CONSTRAINT pk_payments PRIMARY KEY (payment_id),
    CONSTRAINT fk_payments_invoice FOREIGN KEY (invoice_id)
        REFERENCES retail.invoices (invoice_id),
    CONSTRAINT ck_payments_status CHECK (
        payment_status IN ('CAPTURED', 'PENDING', 'REVERSED')
    ),
    CONSTRAINT ck_payments_amount CHECK (amount_paid > 0),
    CONSTRAINT ck_payments_confirmation CHECK (
        confirmation_code IS NULL OR octet_length(confirmation_code) = 16
    )
);

CREATE TABLE retail.audit_log (
    audit_id            bigint NOT NULL,
    event_time          timestamp(0) DEFAULT retail.sysdate(),
    entity_name         varchar(40) NOT NULL,
    entity_id           bigint,
    action_code         varchar(20) NOT NULL,
    actor_name          varchar(80),
    payload             text,
    event_fingerprint   bytea,
    CONSTRAINT pk_audit_log PRIMARY KEY (audit_id),
    CONSTRAINT ck_audit_fingerprint CHECK (
        event_fingerprint IS NULL OR octet_length(event_fingerprint) = 16
    )
);
