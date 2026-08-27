-- Product and price tier fixture rows. Invented SKUs and prices.

-- Untrimmed lower case SKU. Oracle's BEFORE INSERT trigger stores 'SKU-WIDGET'.
INSERT INTO products (
    product_id, sku, product_name, product_group, active_flag,
    base_price, weight_kg, created_on, retired_on
) VALUES (
    92001, '  sku-widget  ', 'Fixture Widget', 'HARDWARE', 'Y',
    10.00, 1.5, DATE '2020-01-01', NULL
);

INSERT INTO products (
    product_id, sku, product_name, product_group, active_flag,
    base_price, weight_kg, created_on, retired_on
) VALUES (
    92002, 'SKU-GADGET', 'Fixture Gadget', 'HARDWARE', 'Y',
    19.99, 0.75, DATE '2020-01-02', NULL
);

-- Zero priced product, used for the zero amount order line.
INSERT INTO products (
    product_id, sku, product_name, product_group, active_flag,
    base_price, weight_kg, created_on, retired_on
) VALUES (
    92003, 'SKU-FREEBIE', 'Fixture Freebie', 'PROMO', 'Y',
    0.00, NULL, DATE '2021-05-05', NULL
);

INSERT INTO products (
    product_id, sku, product_name, product_group, active_flag,
    base_price, weight_kg, created_on, retired_on
) VALUES (
    92004, 'SKU-ASSEMBLY', 'Fixture Assembly', 'HARDWARE', 'Y',
    100.00, 12.25, DATE '2021-06-06', NULL
);

-- Retired product with a NULL group.
INSERT INTO products (
    product_id, sku, product_name, product_group, active_flag,
    base_price, weight_kg, created_on, retired_on
) VALUES (
    92005, 'SKU-RETIRED', 'Fixture Retired Part', NULL, 'N',
    15.50, NULL, DATE '2018-02-02', DATE '2023-12-31'
);

-- Price of 0.005 written into a NUMBER(10, 2) column. Oracle rounds half away
-- from zero on the implicit conversion and stores 0.01.
INSERT INTO price_tiers (
    tier_id, product_id, tier_code, minimum_quantity, unit_price,
    valid_from, valid_to, tier_note
) VALUES (
    92501, 92003, 'PENNY', 1, 0.005,
    DATE '2021-05-05', NULL, 'Half cent tier, checks numeric scale on insert'
);

INSERT INTO price_tiers (
    tier_id, product_id, tier_code, minimum_quantity, unit_price,
    valid_from, valid_to, tier_note
) VALUES (
    92502, 92002, 'STD', 1, 19.99,
    DATE '2020-01-02', NULL, NULL
);

INSERT INTO price_tiers (
    tier_id, product_id, tier_code, minimum_quantity, unit_price,
    valid_from, valid_to, tier_note
) VALUES (
    92503, 92002, 'BULK', 10, 17.50,
    DATE '2020-01-02', DATE '2030-12-31', ''
);

COMMIT;
