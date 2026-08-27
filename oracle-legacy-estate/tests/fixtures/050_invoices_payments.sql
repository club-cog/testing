-- Invoice, invoice line and payment fixture rows. Invented numbers.

-- Partly paid invoice for order 93007 (order total 31.01).
INSERT INTO invoices (
    invoice_id, invoice_number, order_id, issued_on, due_on,
    invoice_status, invoice_total, tax_total
) VALUES (
    94001, 'INV-FIX-1', 93007,
    TO_DATE('2025-01-02 09:00:00', 'YYYY-MM-DD HH24:MI:SS'),
    TO_DATE('2025-02-01 09:00:00', 'YYYY-MM-DD HH24:MI:SS'),
    'ISSUED', 31.01, 2.56
);

-- Voided invoice for order 93001. apply_payment against a VOID invoice takes a
-- different DECODE branch for payment_status and then overwrites the VOID
-- status, which is the behaviour the tests pin.
INSERT INTO invoices (
    invoice_id, invoice_number, order_id, issued_on, due_on,
    invoice_status, invoice_total, tax_total
) VALUES (
    94002, 'INV-FIX-2', 93001,
    TO_DATE('2025-01-05 11:30:00', 'YYYY-MM-DD HH24:MI:SS'),
    TO_DATE('2025-02-04 11:30:00', 'YYYY-MM-DD HH24:MI:SS'),
    'VOID', 20.00, 1.65
);

-- Draft invoice with lines, used by rebuild_invoice_totals. The totals below are
-- deliberately wrong so that the rebuild has something to correct.
INSERT INTO invoices (
    invoice_id, invoice_number, order_id, issued_on, due_on,
    invoice_status, invoice_total, tax_total
) VALUES (
    94003, 'INV-FIX-3', 93004,
    TO_DATE('2025-01-06 16:00:00', 'YYYY-MM-DD HH24:MI:SS'),
    NULL,
    'DRAFT', 999.99, 99.99
);

INSERT INTO invoice_lines (
    invoice_line_id, invoice_id, order_line_number, line_text,
    quantity, line_amount, tax_amount
) VALUES (
    94501, 94003, 1, 'Assembly, four units', 1, 100.00, NULL
);

-- NULL line_amount: the rebuild treats it as zero.
INSERT INTO invoice_lines (
    invoice_line_id, invoice_id, order_line_number, line_text,
    quantity, line_amount, tax_amount
) VALUES (
    94502, 94003, 2, NULL, 2, NULL, NULL
);

-- Zero line_amount with an empty string label.
INSERT INTO invoice_lines (
    invoice_line_id, invoice_id, order_line_number, line_text,
    quantity, line_amount, tax_amount
) VALUES (
    94503, 94003, 3, '', 3, 0.00, 0.00
);

-- Captured payment of 10.00 against invoice 94001.
INSERT INTO payments (
    payment_id, invoice_id, paid_on, payment_method, payment_status, amount_paid
) VALUES (
    95001, 94001, TO_DATE('2025-01-10 08:00:00', 'YYYY-MM-DD HH24:MI:SS'),
    'CARD', 'CAPTURED', 10.00
);

-- Reversed payment of 5.00 against the same invoice. apply_payment sums only
-- CAPTURED rows, so this must not count towards the paid total.
INSERT INTO payments (
    payment_id, invoice_id, paid_on, payment_method, payment_status, amount_paid
) VALUES (
    95002, 94001, TO_DATE('2025-01-11 08:00:00', 'YYYY-MM-DD HH24:MI:SS'),
    'CARD', 'REVERSED', 5.00
);

COMMIT;
