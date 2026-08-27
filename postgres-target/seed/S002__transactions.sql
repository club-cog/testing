-- Deterministic synthetic seed data, part 2: orders, lines, invoices,
-- payments, audit rows.
--
-- Awkward cases in this file:
--
--   order with no lines            5003 (zero totals), 5004 (VOID)
--   order line with NULL amount    order 5002 line 1, feeds summarize_order
--   fractional NUMBER quantity     order 5005 line 1, quantity 2.5
--   boundary order dates           5004 at 1900-01-01, 5011 at 2999-12-31 23:59:59
--   relative recent order          5012, always inside the 90 day window
--   two payments on one invoice    invoice 6001, exposes the v_customer_balance fan-out
--   empty string text column       invoice_lines.line_text on 7003 (see note below)
--   unbilled order                 5002 has no invoice

INSERT INTO retail.orders (
    order_id, order_number, customer_id, bill_address_id, ship_address_id,
    order_status, ordered_at, requested_by, currency_code,
    subtotal_amount, discount_amount, tax_amount, total_amount, note_text, source_token
) VALUES
    (5001, 'ord-5001', 1001, 2001, 2002, 'CLOSED',
     TIMESTAMP '2026-01-15 09:30:00', 'seed-batch', 'USD',
     0, 0, 0, 0, 'Two line order used by most assertions.',
     decode('0102030405060708090a0b0c0d0e0f10', 'hex')),

    (5002, 'ord-5002', 1001, 2001, 2002, 'OPEN',
     TIMESTAMP '2026-02-20 14:45:00', NULL, 'USD',
     0, 0, 0, 0, NULL, NULL),

    (5003, 'ord-5003', 1010, 2004, 2004, 'OPEN',
     TIMESTAMP '2026-03-10 00:00:00', 'seed-batch', 'USD',
     0, 0, 0, 0, NULL, NULL),

    (5004, 'ord-5004', 1001, NULL, NULL, 'VOID',
     TIMESTAMP '1900-01-01 00:00:00', 'seed-batch', 'ZZ',
     0, 0, 0, 0, 'Boundary date, voided.', NULL),

    -- six orders for customer 1002 so pagination has more than one page
    (5005, 'ord-5005', 1002, NULL, 2003, 'OPEN',
     TIMESTAMP '2026-03-01 12:00:00', 'seed-batch', 'USD', 0, 0, 0, 0, NULL, NULL),
    (5006, 'ord-5006', 1002, NULL, 2003, 'OPEN',
     TIMESTAMP '2026-03-02 12:00:00', 'seed-batch', 'USD', 0, 0, 0, 0, NULL, NULL),
    (5007, 'ord-5007', 1002, NULL, 2003, 'HELD',
     TIMESTAMP '2026-03-03 12:00:00', 'seed-batch', 'USD', 0, 0, 0, 0, NULL, NULL),
    (5008, 'ord-5008', 1002, NULL, 2003, 'READY',
     TIMESTAMP '2026-03-04 12:00:00', 'seed-batch', 'USD', 0, 0, 0, 0, NULL, NULL),
    (5009, 'ord-5009', 1002, NULL, 2003, 'CLOSED',
     TIMESTAMP '2026-03-05 12:00:00', 'seed-batch', 'USD', 0, 0, 0, 0, NULL, NULL),
    (5010, 'ord-5010', 1002, NULL, 2003, 'CLOSED',
     TIMESTAMP '2026-03-06 12:00:00', 'seed-batch', 'USD', 0, 0, 0, 0, NULL, NULL),

    (5011, 'ord-5011', 1009, NULL, NULL, 'OPEN',
     TIMESTAMP '2999-12-31 23:59:59', 'seed-batch', 'USD', 0, 0, 0, 0, NULL, NULL);

-- Recent order for 1003, written relative to the clock so the 90 day window in
-- pkg_customer_hier.find_unordered_customers behaves the same whenever the
-- suite runs.
INSERT INTO retail.orders (
    order_id, order_number, customer_id, order_status, ordered_at, requested_by
) VALUES
    (5012, 'ord-5012', 1003, 'OPEN', retail.sysdate() - interval '5 days', 'seed-batch');

INSERT INTO retail.order_lines (
    order_id, line_number, product_id, quantity, unit_price, discount_rate,
    extended_amount, line_note
) VALUES
    (5001, 1, 3001, 2, 10.00, 0, 20.00, 'plain line'),
    (5001, 2, 3003, 1, 99.99, 10, 99.99, 'discounted line'),
    -- NULL extended_amount: summarize_order must report it and not fail
    (5002, 1, 3002, 1, 0.00, 0, NULL, NULL),
    -- fractional quantity, only possible because NUMBER became numeric
    (5005, 1, 3001, 2.5, 10.00, 0, 25.00, 'fractional quantity');

-- Totals are derived, so they are computed by the converted function rather
-- than hard coded. trg_order_lines_ai already set subtotal and total; this adds
-- discount and tax the same way the application does.
SELECT pkg_order_mgmt.refresh_order_total(order_id)
FROM (VALUES (5001::bigint), (5002), (5005)) AS t(order_id);

INSERT INTO retail.invoices (
    invoice_id, invoice_number, order_id, issued_on, due_on, invoice_status,
    invoice_total, tax_total, rendered_pdf, delivery_note
)
SELECT 6001, 'inv-6001', 5001,
       TIMESTAMP '2026-01-16 10:00:00', TIMESTAMP '2026-02-15 10:00:00', 'ISSUED',
       o.total_amount, round(o.total_amount * 0.0825, 2),
       decode('255044462d312e34', 'hex'), 'Seeded delivery note.'
FROM retail.orders o WHERE o.order_id = 5001;

INSERT INTO retail.invoices (
    invoice_id, invoice_number, order_id, issued_on, due_on, invoice_status,
    invoice_total, tax_total, rendered_pdf, delivery_note
) VALUES
    -- zero value invoice
    (6002, 'inv-6002', 5003, TIMESTAMP '2026-03-11 08:00:00', NULL, 'DRAFT',
     0.00, 0.00, NULL, NULL),
    -- void invoice on the boundary date order
    (6003, 'inv-6003', 5004, TIMESTAMP '1900-01-02 00:00:00', NULL, 'VOID',
     0.00, 0.00, NULL, NULL);

INSERT INTO retail.invoice_lines (
    invoice_line_id, invoice_id, order_line_number, line_text, quantity,
    line_amount, tax_amount
) VALUES
    (7001, 6001, 1, 'Fixture Widget A x2', 2, 20.00, NULL),
    (7002, 6001, 2, 'Fixture Widget C x1', 1, 99.99, NULL),
    -- line_text is an empty string, not NULL. Oracle would have stored NULL
    -- here. Only preferred_channel and validated_flag get the trigger based
    -- empty string normalisation, because those are the two columns whose
    -- CHECK constraints depended on it. Every other text column keeps the
    -- PostgreSQL meaning of '', which is a real value. Loader review item,
    -- recorded in CONVERSION-NOTES.md.
    (7003, 6002, 1, '', 1, 0.00, NULL);

INSERT INTO retail.payments (
    payment_id, invoice_id, paid_on, payment_method, payment_status,
    amount_paid, confirmation_code, gateway_note
) VALUES
    (8001, 6001, TIMESTAMP '2026-01-20 11:00:00', 'CARD', 'CAPTURED',
     50.00, decode('a0a1a2a3a4a5a6a7a8a9aaabacadaeaf', 'hex'), NULL),
    (8002, 6001, TIMESTAMP '2026-01-25 11:00:00', 'ACH', 'CAPTURED',
     30.00, NULL, 'second payment on the same invoice');

INSERT INTO retail.audit_log (
    audit_id, event_time, entity_name, entity_id, action_code, actor_name,
    payload, event_fingerprint
) VALUES
    (9001, TIMESTAMP '2026-01-16 10:00:01', 'INVOICE', 6001, 'SEEDED', 'seed-batch',
     'seeded invoice 6001', decode('0f0e0d0c0b0a09080706050403020100', 'hex'));
