-- Customer fixture rows: a five level hierarchy plus awkward singletons.
-- Invented data. No real company names.
--
-- Hierarchy shape (parent -> child):
--   90001 ROOT-CO
--     90002 REGION-NORTH
--       90004 BRANCH-N1
--         90006 DEPT-N1A            (status H, still part of the tree)
--           90007 TEAM-N1A1         (depth 5)
--       90005 BRANCH-N2
--     90003 REGION-SOUTH
--
-- Standalone rows: 90008..90012.

INSERT INTO customers (
    customer_id, customer_code, display_name, status, preferred_channel,
    credit_limit, joined_on, last_contacted_on, parent_customer_id
) VALUES (
    90001, 'ROOT-CO', 'Root Holding Fixture', 'A', 'EMAIL',
    50000.00, DATE '2019-01-01', DATE '2025-06-01', NULL
);

INSERT INTO customers (
    customer_id, customer_code, display_name, status, preferred_channel,
    credit_limit, joined_on, last_contacted_on, parent_customer_id
) VALUES (
    90002, 'REGION-NORTH', 'North Region Fixture', 'A', 'PHONE',
    20000.00, DATE '2019-02-01', DATE '2025-05-15', 90001
);

INSERT INTO customers (
    customer_id, customer_code, display_name, status, preferred_channel,
    credit_limit, joined_on, last_contacted_on, parent_customer_id
) VALUES (
    90003, 'REGION-SOUTH', 'South Region Fixture', 'A', 'PHONE',
    20000.00, DATE '2019-02-01', NULL, 90001
);

INSERT INTO customers (
    customer_id, customer_code, display_name, status, preferred_channel,
    credit_limit, joined_on, last_contacted_on, parent_customer_id
) VALUES (
    90004, 'BRANCH-N1', 'North Branch One Fixture', 'A', 'EMAIL',
    5000.00, DATE '2020-03-15', NULL, 90002
);

INSERT INTO customers (
    customer_id, customer_code, display_name, status, preferred_channel,
    credit_limit, joined_on, last_contacted_on, parent_customer_id
) VALUES (
    90005, 'BRANCH-N2', 'North Branch Two Fixture', 'A', 'EMAIL',
    5000.00, DATE '2020-03-16', NULL, 90002
);

-- Held status inside the tree: CONNECT BY still walks through it because
-- print_tree and descendant_count do not filter on status.
INSERT INTO customers (
    customer_id, customer_code, display_name, status, preferred_channel,
    credit_limit, joined_on, last_contacted_on, parent_customer_id
) VALUES (
    90006, 'DEPT-N1A', 'North Department A Fixture', 'H', 'EMAIL',
    NULL, DATE '2021-07-01', NULL, 90004
);

INSERT INTO customers (
    customer_id, customer_code, display_name, status, preferred_channel,
    credit_limit, joined_on, last_contacted_on, parent_customer_id
) VALUES (
    90007, 'TEAM-N1A1', 'North Team A1 Fixture', 'A', 'EMAIL',
    NULL, DATE '2021-08-01', NULL, 90006
);

-- Ordered long ago: outside the 90 day window used by
-- pkg_customer_hier.find_unordered_customers.
INSERT INTO customers (
    customer_id, customer_code, display_name, status, preferred_channel,
    credit_limit, joined_on, last_contacted_on, parent_customer_id
) VALUES (
    90008, 'SOLO-STALE', 'Stale Buyer Fixture', 'A', 'EMAIL',
    1000.00, DATE '2022-01-01', NULL, NULL
);

-- Ordered recently: inside the 90 day window.
INSERT INTO customers (
    customer_id, customer_code, display_name, status, preferred_channel,
    credit_limit, joined_on, last_contacted_on, parent_customer_id
) VALUES (
    90009, 'SOLO-RECENT', 'Recent Buyer Fixture', 'A', 'EMAIL',
    1000.00, DATE '2022-02-01', NULL, NULL
);

-- Inactive: excluded from find_unordered_customers by status.
INSERT INTO customers (
    customer_id, customer_code, display_name, status, preferred_channel,
    credit_limit, joined_on, last_contacted_on, parent_customer_id
) VALUES (
    90010, 'SOLO-INACTIVE', 'Inactive Buyer Fixture', 'I', 'EMAIL',
    0.00, DATE '2022-03-01', NULL, NULL
);

-- Empty string in preferred_channel. On Oracle the value becomes NULL and the
-- check constraint (preferred_channel <> '') is not violated because the
-- comparison evaluates to UNKNOWN. On PostgreSQL the same statement stores a
-- zero length string and the check constraint rejects the row.
INSERT INTO customers (
    customer_id, customer_code, display_name, status, preferred_channel,
    credit_limit, joined_on, last_contacted_on, parent_customer_id
) VALUES (
    90011, 'EMPTY-CHANNEL', 'Empty Channel Fixture', 'A', '',
    NULL, DATE '2023-04-01', NULL, NULL
);

-- Untrimmed lower case code and a NULL credit limit. On Oracle the BEFORE
-- INSERT trigger stores 'MIXED-CASE'. On PostgreSQL, with no equivalent
-- trigger, the stored value keeps its spaces and case.
INSERT INTO customers (
    customer_id, customer_code, display_name, status, preferred_channel,
    credit_limit, joined_on, last_contacted_on, parent_customer_id
) VALUES (
    90012, '  mixed-case  ', 'Mixed Case Code Fixture', 'A', 'MAIL',
    NULL, DATE '2023-05-01', NULL, NULL
);

COMMIT;
