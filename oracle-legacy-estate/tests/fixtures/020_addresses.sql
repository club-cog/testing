-- Address fixture rows. Invented street data.

INSERT INTO addresses (
    address_id, customer_id, address_kind, line_one, line_two,
    city_name, region_code, postal_code, country_code, validated_flag, created_at
) VALUES (
    91001, 90001, 'BILL', '1 Fixture Way', NULL,
    'Testville', 'TS', '00001', 'ZZ', 'Y', DATE '2019-01-01'
);

INSERT INTO addresses (
    address_id, customer_id, address_kind, line_one, line_two,
    city_name, region_code, postal_code, country_code, validated_flag, created_at
) VALUES (
    91002, 90001, 'SHIP', '2 Fixture Way', 'Dock 4',
    'Testville', 'TS', '00001', 'ZZ', 'Y', DATE '2019-01-01'
);

-- Lower case country code. Oracle's BEFORE INSERT trigger upper cases it.
INSERT INTO addresses (
    address_id, customer_id, address_kind, line_one, line_two,
    city_name, region_code, postal_code, country_code, validated_flag, created_at
) VALUES (
    91003, 90003, 'BILL', '3 Fixture Way', NULL,
    'Sampleton', NULL, NULL, 'zz', 'N', DATE '2020-06-01'
);

-- Empty string in validated_flag: same Oracle versus PostgreSQL constraint
-- question as customers.preferred_channel.
INSERT INTO addresses (
    address_id, customer_id, address_kind, line_one, line_two,
    city_name, region_code, postal_code, country_code, validated_flag, created_at
) VALUES (
    91004, 90009, 'SHIP', '4 Fixture Way', NULL,
    'Sampleton', 'SS', '00004', 'ZZ', '', DATE '2022-02-02'
);

-- NULL country code relies on the trigger default of 'ZZ' on Oracle and on the
-- column default on PostgreSQL. The two paths are not the same: the trigger
-- fires even when the caller passes NULL explicitly, the column default does not.
INSERT INTO addresses (
    address_id, customer_id, address_kind, line_one, line_two,
    city_name, region_code, postal_code, country_code, validated_flag, created_at
) VALUES (
    91005, 90012, 'OTHER', '5 Fixture Way', NULL,
    'Sampleton', NULL, NULL, NULL, 'N', DATE '2023-05-02'
);

COMMIT;
