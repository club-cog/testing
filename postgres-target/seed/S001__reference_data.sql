-- Deterministic synthetic seed data, part 1: customers, addresses, products,
-- price tiers.
--
-- Everything here is invented for the migration fixture. Keys are explicit so
-- tests can assert on them. The awkward cases are on purpose and each one is
-- labelled:
--
--   NULLs               credit_limit, last_contacted_on, line_two, weight_kg, description
--   empty strings       preferred_channel, validated_flag (Oracle stored NULL)
--   zero amounts        products.base_price, price_tiers.unit_price
--   deep hierarchy      1001 -> 1002 -> 1004 -> 1005 -> 1006, five levels
--   boundary dates      1900-01-01, 2000-02-29, 2999-12-31 23:59:59
--   binary values       RAW(16) as exactly 16 bytes, BLOB as bytea

INSERT INTO retail.customers (
    customer_id, customer_code, display_name, status, preferred_channel,
    credit_limit, joined_on, last_contacted_on, parent_customer_id,
    profile_note, avatar_blob, external_ref
) VALUES
    -- root of the deep hierarchy
    (1001, 'c-root', 'Root Holding Fixture', 'A', 'EMAIL',
     50000.00, TIMESTAMP '2020-03-01 08:00:00', TIMESTAMP '2026-06-01 17:30:00', NULL,
     'Fixture root account. Long CLOB text is fine here.',
     decode('89504e470d0a1a0a', 'hex'),
     decode('00112233445566778899aabbccddeeff', 'hex')),

    -- inserted before its sibling 1002 on purpose: sibling ordering in
    -- print_tree must come from customer_code, not insert order
    (1003, 'c-west', 'West Region Fixture', 'A', NULL,
     12000.00, TIMESTAMP '2021-07-15 09:15:00', NULL, 1001,
     NULL, NULL, NULL),
    (1002, 'c-east', 'East Region Fixture', 'A', 'PHONE',
     12000.00, TIMESTAMP '2021-07-15 09:15:00', NULL, 1001,
     NULL, NULL, NULL),
    (1004, 'c-east-1', 'East District One Fixture', 'A', NULL,
     3000.00, TIMESTAMP '2022-02-28 10:00:00', NULL, 1002,
     NULL, NULL, NULL),
    (1005, 'c-east-1-a', 'East District One Site A Fixture', 'A', NULL,
     NULL, TIMESTAMP '2023-11-30 11:11:11', NULL, 1004,
     NULL, NULL, NULL),
    (1006, 'c-east-1-a-1', 'East District One Site A Desk One Fixture', 'A', NULL,
     0.00, TIMESTAMP '2024-01-02 12:00:00', NULL, 1005,
     NULL, NULL, NULL),

    -- inactive, never ordered
    (1007, 'c-solo', 'Dormant Account Fixture', 'I', NULL,
     NULL, TIMESTAMP '2019-05-05 13:45:00', NULL, NULL,
     NULL, NULL, NULL),

    -- legacy loader style row: empty string channel, no credit limit.
    -- Oracle stored '' as NULL; trigger trg_customers_empty_string does the same.
    (1008, 'c-empty', 'Empty String Loader Fixture', 'A', '',
     NULL, TIMESTAMP '2025-01-01 00:00:00', NULL, NULL,
     '', NULL, NULL),

    -- boundary dates, including a leap day and a far future timestamp
    (1009, 'c-dates', 'Boundary Date Fixture', 'A', 'EDI',
     999999.99, TIMESTAMP '1900-01-01 00:00:00', TIMESTAMP '2000-02-29 23:59:59', NULL,
     NULL, NULL, decode('ffffffffffffffffffffffffffffffff', 'hex')),

    -- everything zero
    (1010, 'c-zero', 'Zero Amount Fixture', 'A', 'WEB',
     0.00, TIMESTAMP '2026-04-01 06:00:00', NULL, NULL,
     NULL, NULL, NULL);

INSERT INTO retail.addresses (
    address_id, customer_id, address_kind, line_one, line_two, city_name,
    region_code, postal_code, country_code, validated_flag, created_at
) VALUES
    -- lowercase country code, uppercased by trg_addresses_bi
    -- empty validated_flag, turned into NULL like Oracle
    (2001, 1001, 'BILL', '1 Fixture Way', NULL, 'Fixtureville',
     'FX', '00001', 'us', '', TIMESTAMP '2020-03-01 08:05:00'),
    (2002, 1001, 'SHIP', '2 Fixture Way', 'Dock B', 'Fixtureville',
     'FX', '00001', 'US', 'Y', TIMESTAMP '2020-03-01 08:06:00'),
    (2003, 1002, 'SHIP', '3 Fixture Way', NULL, 'East Fixture',
     NULL, NULL, NULL, NULL, TIMESTAMP '2021-07-15 09:20:00'),
    (2004, 1010, 'BILL', '4 Fixture Way', NULL, 'Zero City',
     'ZZ', '00000', 'ZZ', 'N', TIMESTAMP '2026-04-01 06:05:00');

INSERT INTO retail.products (
    product_id, sku, product_name, product_group, active_flag, base_price,
    weight_kg, description, image_blob, created_on, retired_on
) VALUES
    (3001, 'sku-a', 'Fixture Widget A', 'WIDGETS', 'Y', 10.00,
     1.5, 'Standard fixture widget.', NULL, TIMESTAMP '2020-01-01 00:00:00', NULL),
    -- zero price, unconstrained NUMBER weight left NULL, CLOB NULL
    (3002, 'sku-b', 'Fixture Sample B', 'SAMPLES', 'Y', 0.00,
     NULL, NULL, NULL, TIMESTAMP '2021-06-01 00:00:00', NULL),
    (3003, 'sku-c', 'Fixture Widget C', 'WIDGETS', 'N', 99.99,
     0.125, 'Retired fixture widget.', decode('cafebabe', 'hex'),
     TIMESTAMP '2019-01-01 00:00:00', TIMESTAMP '2025-12-31 23:59:59');

INSERT INTO retail.price_tiers (
    tier_id, product_id, tier_code, minimum_quantity, unit_price,
    valid_from, valid_to, tier_note
) VALUES
    (4001, 3001, 'STD', 1, 10.00, TIMESTAMP '2020-01-01 00:00:00', NULL, NULL),
    (4002, 3001, 'BULK', 10, 8.50, TIMESTAMP '2020-01-01 00:00:00',
     TIMESTAMP '2030-01-01 00:00:00', 'Volume tier'),
    -- zero unit price, valid_from equal to valid_to boundary of ck_price_tiers_dates
    (4003, 3002, 'STD', 1, 0.00, TIMESTAMP '2021-06-01 00:00:00',
     TIMESTAMP '2021-06-01 00:00:00', '');
