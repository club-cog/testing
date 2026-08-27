-- Order and order line fixture rows. Invented order numbers.
--
-- Two rows use SYSDATE arithmetic on purpose, because
-- pkg_customer_hier.find_unordered_customers filters on SYSDATE - 90 and a
-- fixed literal would drift out of the window as time passes. Everything else
-- uses fixed literals so that ordering and pagination are deterministic.
-- On PostgreSQL, replace SYSDATE with LOCALTIMESTAMP.
--
-- The order totals below are the values Oracle's AFTER INSERT trigger on
-- order_lines leaves behind, which is the sum of extended_amount with no tax.
-- They are written explicitly so that the same INSERTs give the same rows on
-- PostgreSQL, where that trigger may not exist yet.

-- Customer 90009 SOLO-RECENT: inside the 90 day window.
INSERT INTO orders (
    order_id, order_number, customer_id, bill_address_id, ship_address_id,
    order_status, ordered_at, requested_by, currency_code,
    subtotal_amount, discount_amount, tax_amount, total_amount
) VALUES (
    93001, 'PO-RECENT-1', 90009, NULL, 91004,
    'CLOSED', SYSDATE - 10, 'FIXTURE-USER', 'ZZ',
    20.00, 0, 0, 20.00
);

-- Customer 90008 SOLO-STALE: 100 days old, so outside the 90 day window.
INSERT INTO orders (
    order_id, order_number, customer_id, bill_address_id, ship_address_id,
    order_status, ordered_at, requested_by, currency_code,
    subtotal_amount, discount_amount, tax_amount, total_amount
) VALUES (
    93002, 'PO-STALE-1', 90008, NULL, NULL,
    'CLOSED', SYSDATE - 100, 'FIXTURE-USER', 'ZZ',
    0, 0, 0, 0
);

-- Customer 90001 ROOT-CO: five orders with distinct timestamps. These drive the
-- pagination tests, so no two ordered_at values may tie.
INSERT INTO orders (
    order_id, order_number, customer_id, bill_address_id, ship_address_id,
    order_status, ordered_at, requested_by, currency_code,
    subtotal_amount, discount_amount, tax_amount, total_amount
) VALUES (
    93003, 'PO-PAGE-1', 90001, 91001, 91002,
    'OPEN', TO_DATE('2024-01-15 10:00:00', 'YYYY-MM-DD HH24:MI:SS'), 'BATCH', 'ZZ',
    0, 0, 0, 0
);

-- Leap day.
INSERT INTO orders (
    order_id, order_number, customer_id, bill_address_id, ship_address_id,
    order_status, ordered_at, requested_by, currency_code,
    subtotal_amount, discount_amount, tax_amount, total_amount
) VALUES (
    93004, 'PO-PAGE-2', 90001, 91001, 91002,
    'OPEN', TO_DATE('2024-02-29 08:30:00', 'YYYY-MM-DD HH24:MI:SS'), 'BATCH', 'ZZ',
    100.00, 0, 0, 100.00
);

-- Last second of a month.
INSERT INTO orders (
    order_id, order_number, customer_id, bill_address_id, ship_address_id,
    order_status, ordered_at, requested_by, currency_code,
    subtotal_amount, discount_amount, tax_amount, total_amount
) VALUES (
    93005, 'PO-PAGE-3', 90001, 91001, 91002,
    'HELD', TO_DATE('2024-03-31 23:59:59', 'YYYY-MM-DD HH24:MI:SS'), 'ANNA-FIXTURE', 'ZZ',
    59.97, 0, 0, 59.97
);

-- Midnight, which is the only case where a DATE column looks date-only.
INSERT INTO orders (
    order_id, order_number, customer_id, bill_address_id, ship_address_id,
    order_status, ordered_at, requested_by, currency_code,
    subtotal_amount, discount_amount, tax_amount, total_amount
) VALUES (
    93006, 'PO-PAGE-4', 90001, 91001, 91002,
    'READY', TO_DATE('2024-06-30 00:00:00', 'YYYY-MM-DD HH24:MI:SS'), 'BATCH', 'ZZ',
    0.00, 0, 0, 0.00
);

INSERT INTO orders (
    order_id, order_number, customer_id, bill_address_id, ship_address_id,
    order_status, ordered_at, requested_by, currency_code,
    subtotal_amount, discount_amount, tax_amount, total_amount
) VALUES (
    93007, 'PO-PAGE-5', 90001, 91001, 91002,
    'CLOSED', TO_DATE('2024-12-31 12:00:00', 'YYYY-MM-DD HH24:MI:SS'), 'BATCH', 'ZZ',
    31.01, 0, 0, 31.01
);

-- Boundary date: last second of 1999, for date arithmetic and sorting.
INSERT INTO orders (
    order_id, order_number, customer_id, bill_address_id, ship_address_id,
    order_status, ordered_at, requested_by, currency_code,
    subtotal_amount, discount_amount, tax_amount, total_amount
) VALUES (
    93008, 'PO-BOUNDARY-1', 90012, NULL, 91005,
    'VOID', TO_DATE('1999-12-31 23:59:59', 'YYYY-MM-DD HH24:MI:SS'), NULL, 'ZZ',
    0, 0, 0, 0
);

-- Empty string requested_by. Oracle stores NULL. PostgreSQL stores ''.
INSERT INTO orders (
    order_id, order_number, customer_id, bill_address_id, ship_address_id,
    order_status, ordered_at, requested_by, currency_code,
    subtotal_amount, discount_amount, tax_amount, total_amount
) VALUES (
    93009, 'PO-EMPTYSTR-1', 90011, NULL, NULL,
    'OPEN', TO_DATE('2024-04-01 09:15:00', 'YYYY-MM-DD HH24:MI:SS'), '', 'ZZ',
    0, 0, 0, 0
);

-- Billing fixture order.
INSERT INTO orders (
    order_id, order_number, customer_id, bill_address_id, ship_address_id,
    order_status, ordered_at, requested_by, currency_code,
    subtotal_amount, discount_amount, tax_amount, total_amount
) VALUES (
    93010, 'PO-BILLING-1', 90003, 91003, NULL,
    'READY', TO_DATE('2025-02-10 14:45:00', 'YYYY-MM-DD HH24:MI:SS'), 'BATCH', 'ZZ',
    100.00, 0, 0, 100.00
);

INSERT INTO order_lines (
    order_id, line_number, product_id, quantity, unit_price,
    discount_rate, extended_amount, line_note
) VALUES (93001, 1, 92001, 2, 10.00, 0, 20.00, NULL);

INSERT INTO order_lines (
    order_id, line_number, product_id, quantity, unit_price,
    discount_rate, extended_amount, line_note
) VALUES (93004, 1, 92004, 1, 100.00, 0, 100.00, NULL);

INSERT INTO order_lines (
    order_id, line_number, product_id, quantity, unit_price,
    discount_rate, extended_amount, line_note
) VALUES (93005, 1, 92002, 3, 19.99, 0, 59.97, 'Rounding case: 8.25 percent of 59.97');

-- Zero amount line: quantity must stay above zero because of the check
-- constraint, so the zero comes from the unit price.
INSERT INTO order_lines (
    order_id, line_number, product_id, quantity, unit_price,
    discount_rate, extended_amount, line_note
) VALUES (93006, 1, 92003, 5, 0.00, 0, 0.00, 'Zero amount line');

INSERT INTO order_lines (
    order_id, line_number, product_id, quantity, unit_price,
    discount_rate, extended_amount, line_note
) VALUES (93007, 1, 92005, 2, 15.50, 0, 31.00, NULL);

-- One cent line, so that the order total is not a round number.
INSERT INTO order_lines (
    order_id, line_number, product_id, quantity, unit_price,
    discount_rate, extended_amount, line_note
) VALUES (93007, 2, 92003, 1, 0.01, 0, 0.01, '');

INSERT INTO order_lines (
    order_id, line_number, product_id, quantity, unit_price,
    discount_rate, extended_amount, line_note
) VALUES (93010, 1, 92004, 4, 25.00, 0, 100.00, NULL);

COMMIT;
