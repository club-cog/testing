CREATE OR REPLACE PACKAGE BODY ut_pkg_billing AS

    -- pkg_billing.write_billing_log runs with PRAGMA AUTONOMOUS_TRANSACTION and
    -- commits, so audit rows written during a test are not rolled back with the
    -- rest of the test. test_teardown removes them autonomously. That is the
    -- honest way to test this package: hiding the commit behind the framework
    -- would also hide the behaviour a migration has to reproduce.

    PROCEDURE suite_setup IS
        l_invoice_count PLS_INTEGER;
    BEGIN
        SELECT COUNT(*)
        INTO l_invoice_count
        FROM invoices
        WHERE invoice_id BETWEEN ut_estate_fixture.c_fixture_low
                             AND ut_estate_fixture.c_fixture_high;

        IF l_invoice_count <> 3 THEN
            RAISE_APPLICATION_ERROR(
                -20002,
                'Fixture not loaded: expected 3 fixture invoices, found '
                || l_invoice_count
            );
        END IF;

        DBMS_OUTPUT.ENABLE(1000000);
    END suite_setup;

    PROCEDURE test_setup IS
    BEGIN
        ut_estate_fixture.start_output_capture;
    END test_setup;

    PROCEDURE test_teardown IS
    BEGIN
        ut_estate_fixture.purge_generated_audit_rows;
    END test_teardown;

    PROCEDURE suite_teardown IS
    BEGIN
        ut_estate_fixture.purge_generated_audit_rows;
    END suite_teardown;

    ---------------------------------------------------------------------------
    -- issue_invoice
    ---------------------------------------------------------------------------

    PROCEDURE issue_creates_issued_invoice IS
        l_invoice_id invoices.invoice_id%TYPE;
        l_status     invoices.invoice_status%TYPE;
        l_total      invoices.invoice_total%TYPE;
        l_order_id   invoices.order_id%TYPE;
    BEGIN
        pkg_billing.issue_invoice(
            p_order_id   => ut_estate_fixture.c_order_billing,
            p_invoice_id => l_invoice_id
        );

        SELECT invoice_status, invoice_total, order_id
        INTO l_status, l_total, l_order_id
        FROM invoices
        WHERE invoice_id = l_invoice_id;

        ut.expect(l_invoice_id).to_be_not_null();
        ut.expect(l_status).to_equal('ISSUED');
        -- Copied from orders.total_amount, which the fixture sets to 100.00.
        ut.expect(l_total).to_equal(100.00);
        ut.expect(l_order_id).to_equal(ut_estate_fixture.c_order_billing);
    END issue_creates_issued_invoice;

    PROCEDURE issue_numbers_from_sequence IS
        l_invoice_id invoices.invoice_id%TYPE;
        l_number     invoices.invoice_number%TYPE;
    BEGIN
        pkg_billing.issue_invoice(
            p_order_id   => ut_estate_fixture.c_order_billing,
            p_invoice_id => l_invoice_id
        );

        SELECT invoice_number
        INTO l_number
        FROM invoices
        WHERE invoice_id = l_invoice_id;

        -- NEXTVAL builds the number, CURRVAL fills the key, so the two always
        -- agree inside a single call. Any migration that replaces the sequence
        -- with an identity column has to keep that coupling.
        ut.expect(l_number).to_equal('INV-' || TO_CHAR(l_invoice_id));
    END issue_numbers_from_sequence;

    PROCEDURE issue_rounds_tax_on_insert IS
        l_invoice_id invoices.invoice_id%TYPE;
        l_tax_total  invoices.tax_total%TYPE;
    BEGIN
        -- Order 93005 totals 59.97. The procedure inserts 59.97 * 0.0825, which
        -- is 4.947525, with no ROUND call. The NUMBER(14, 2) column rounds it.
        pkg_billing.issue_invoice(
            p_order_id   => ut_estate_fixture.c_order_page_3,
            p_invoice_id => l_invoice_id
        );

        SELECT tax_total
        INTO l_tax_total
        FROM invoices
        WHERE invoice_id = l_invoice_id;

        ut.expect(l_tax_total).to_equal(4.95);
    END issue_rounds_tax_on_insert;

    PROCEDURE issue_due_on_is_plus_30_days IS
        l_invoice_id invoices.invoice_id%TYPE;
        l_issued_on  invoices.issued_on%TYPE;
        l_due_on     invoices.due_on%TYPE;
    BEGIN
        pkg_billing.issue_invoice(
            p_order_id   => ut_estate_fixture.c_order_billing,
            p_invoice_id => l_invoice_id
        );

        SELECT issued_on, due_on
        INTO l_issued_on, l_due_on
        FROM invoices
        WHERE invoice_id = l_invoice_id;

        -- SYSDATE + 30 adds 30 days and keeps the time of day, because DATE in
        -- this estate is really a timestamp with second precision.
        ut.expect(TRUNC(l_due_on) - TRUNC(l_issued_on)).to_equal(30);
        ut.expect(TO_CHAR(l_due_on, 'HH24:MI:SS'))
            .to_equal(TO_CHAR(l_issued_on, 'HH24:MI:SS'));
    END issue_due_on_is_plus_30_days;

    PROCEDURE issue_writes_audit_row IS
        l_invoice_id  invoices.invoice_id%TYPE;
        l_action      audit_log.action_code%TYPE;
        l_entity      audit_log.entity_name%TYPE;
        l_actor       audit_log.actor_name%TYPE;
        l_payload     VARCHAR2(4000);
    BEGIN
        pkg_billing.issue_invoice(
            p_order_id   => ut_estate_fixture.c_order_billing,
            p_invoice_id => l_invoice_id
        );

        SELECT entity_name, action_code, actor_name, TO_CHAR(payload)
        INTO l_entity, l_action, l_actor, l_payload
        FROM audit_log
        WHERE entity_id = l_invoice_id
          AND action_code = 'ISSUED';

        ut.expect(l_entity).to_equal('INVOICE');
        ut.expect(l_action).to_equal('ISSUED');
        ut.expect(l_payload).to_equal('INV-' || TO_CHAR(l_invoice_id));
        -- SYS_CONTEXT never returns NULL for a logged in session, so the NVL to
        -- 'BATCH' is unreachable here. It is recorded as dead code, not tested.
        ut.expect(l_actor).to_be_not_null();
    END issue_writes_audit_row;

    PROCEDURE issue_audit_row_is_committed IS
        l_invoice_id    invoices.invoice_id%TYPE;
        l_invoice_rows  PLS_INTEGER;
        l_audit_rows    PLS_INTEGER;
    BEGIN
        pkg_billing.issue_invoice(
            p_order_id   => ut_estate_fixture.c_order_billing,
            p_invoice_id => l_invoice_id
        );

        ROLLBACK;

        SELECT COUNT(*)
        INTO l_invoice_rows
        FROM invoices
        WHERE invoice_id = l_invoice_id;

        SELECT COUNT(*)
        INTO l_audit_rows
        FROM audit_log
        WHERE entity_id = l_invoice_id;

        -- The invoice is gone, the audit trail says it was issued. Any
        -- conversion that turns write_billing_log into a plain insert changes
        -- this, and any conversion that keeps it needs a second connection.
        ut.expect(l_invoice_rows).to_equal(0);
        ut.expect(l_audit_rows).to_equal(1);

        ut_estate_fixture.purge_audit_rows(l_invoice_id);
    END issue_audit_row_is_committed;

    PROCEDURE issue_unknown_order_raises IS
        l_invoice_id invoices.invoice_id%TYPE;
    BEGIN
        BEGIN
            pkg_billing.issue_invoice(
                p_order_id   => ut_estate_fixture.c_missing_order,
                p_invoice_id => l_invoice_id
            );
            ut.fail('Expected ORA-20911 for an unknown order');
        EXCEPTION
            WHEN OTHERS THEN
                -- The WHEN OTHERS handler replaces NO_DATA_FOUND with the
                -- estate code, so callers cannot tell a missing order from a
                -- constraint failure except by reading the message text.
                ut.expect(SQLCODE).to_equal(-20911);
                ut.expect(SQLERRM).to_be_like('%Invoice creation failed%');
        END;
    END issue_unknown_order_raises;

    PROCEDURE issue_second_invoice_raises IS
        l_invoice_id invoices.invoice_id%TYPE;
    BEGIN
        -- Order 93007 already carries fixture invoice 94001 and
        -- uk_invoices_order allows one invoice per order.
        BEGIN
            pkg_billing.issue_invoice(
                p_order_id   => ut_estate_fixture.c_order_page_5,
                p_invoice_id => l_invoice_id
            );
            ut.fail('Expected ORA-20911 for a duplicate invoice');
        EXCEPTION
            WHEN OTHERS THEN
                ut.expect(SQLCODE).to_equal(-20911);
        END;
    END issue_second_invoice_raises;

    ---------------------------------------------------------------------------
    -- apply_payment
    ---------------------------------------------------------------------------

    PROCEDURE payment_full_marks_paid IS
        l_status  invoices.invoice_status%TYPE;
        l_pay_row payments.payment_status%TYPE;
        l_method  payments.payment_method%TYPE;
    BEGIN
        -- Invoice 94001 totals 31.01 with 10.00 already captured.
        pkg_billing.apply_payment(
            p_invoice_id => ut_estate_fixture.c_invoice_issued,
            p_amount     => 21.01,
            p_method     => 'CARD'
        );

        SELECT invoice_status
        INTO l_status
        FROM invoices
        WHERE invoice_id = ut_estate_fixture.c_invoice_issued;

        SELECT payment_status, payment_method
        INTO l_pay_row, l_method
        FROM payments
        WHERE invoice_id = ut_estate_fixture.c_invoice_issued
          AND payment_id >= 100000;

        ut.expect(l_status).to_equal('PAID');
        ut.expect(l_pay_row).to_equal('CAPTURED');
        ut.expect(l_method).to_equal('CARD');
    END payment_full_marks_paid;

    PROCEDURE payment_short_marks_partial IS
        l_status invoices.invoice_status%TYPE;
    BEGIN
        pkg_billing.apply_payment(
            p_invoice_id => ut_estate_fixture.c_invoice_issued,
            p_amount     => 5.00,
            p_method     => 'CARD'
        );

        SELECT invoice_status
        INTO l_status
        FROM invoices
        WHERE invoice_id = ut_estate_fixture.c_invoice_issued;

        ut.expect(l_status).to_equal('PARTIAL');
    END payment_short_marks_partial;

    PROCEDURE payment_ignores_reversed IS
        l_status invoices.invoice_status%TYPE;
    BEGIN
        -- Captured 10.00 plus this 16.01 is 26.01, short of the 31.01 total.
        -- If the REVERSED fixture payment of 5.00 were counted the invoice
        -- would flip to PAID instead, so this value discriminates.
        pkg_billing.apply_payment(
            p_invoice_id => ut_estate_fixture.c_invoice_issued,
            p_amount     => 16.01,
            p_method     => 'CARD'
        );

        SELECT invoice_status
        INTO l_status
        FROM invoices
        WHERE invoice_id = ut_estate_fixture.c_invoice_issued;

        ut.expect(l_status).to_equal('PARTIAL');
    END payment_ignores_reversed;

    PROCEDURE payment_null_method_is_unknown IS
        l_method payments.payment_method%TYPE;
    BEGIN
        pkg_billing.apply_payment(
            p_invoice_id => ut_estate_fixture.c_invoice_issued,
            p_amount     => 1.00,
            p_method     => NULL
        );

        SELECT payment_method
        INTO l_method
        FROM payments
        WHERE invoice_id = ut_estate_fixture.c_invoice_issued
          AND payment_id >= 100000;

        ut.expect(l_method).to_equal('UNKNOWN');
    END payment_null_method_is_unknown;

    PROCEDURE payment_empty_method_is_unknown IS
        l_method payments.payment_method%TYPE;
    BEGIN
        -- Oracle only. On PostgreSQL NVL('' , 'UNKNOWN') keeps the empty string
        -- and the payment is stored with a blank method.
        pkg_billing.apply_payment(
            p_invoice_id => ut_estate_fixture.c_invoice_issued,
            p_amount     => 1.00,
            p_method     => ''
        );

        SELECT payment_method
        INTO l_method
        FROM payments
        WHERE invoice_id = ut_estate_fixture.c_invoice_issued
          AND payment_id >= 100000;

        ut.expect(l_method).to_equal('UNKNOWN');
    END payment_empty_method_is_unknown;

    PROCEDURE payment_on_void_invoice IS
        l_pay_status payments.payment_status%TYPE;
        l_inv_status invoices.invoice_status%TYPE;
    BEGIN
        -- Invoice 94002 is VOID with a total of 20.00.
        pkg_billing.apply_payment(
            p_invoice_id => ut_estate_fixture.c_invoice_void,
            p_amount     => 20.00,
            p_method     => 'CHECK'
        );

        SELECT payment_status
        INTO l_pay_status
        FROM payments
        WHERE invoice_id = ut_estate_fixture.c_invoice_void
          AND payment_id >= 100000;

        SELECT invoice_status
        INTO l_inv_status
        FROM invoices
        WHERE invoice_id = ut_estate_fixture.c_invoice_void;

        -- The DECODE parks the payment as PENDING, then the unconditional
        -- UPDATE at the end of the procedure overwrites VOID with PAID. The
        -- AFTER INSERT trigger on payments, which protects VOID, is undone by
        -- the procedure that fired it.
        ut.expect(l_pay_status).to_equal('PENDING');
        ut.expect(l_inv_status).to_equal('PAID');
    END payment_on_void_invoice;

    PROCEDURE payment_unknown_invoice_raises IS
    BEGIN
        BEGIN
            pkg_billing.apply_payment(
                p_invoice_id => ut_estate_fixture.c_missing_invoice,
                p_amount     => 5.00,
                p_method     => 'CARD'
            );
            ut.fail('Expected ORA-20912 for an unknown invoice');
        EXCEPTION
            WHEN OTHERS THEN
                ut.expect(SQLCODE).to_equal(-20912);
                ut.expect(SQLERRM).to_be_like('%Invoice does not exist%');
        END;
    END payment_unknown_invoice_raises;

    PROCEDURE payment_zero_amount_raises IS
    BEGIN
        BEGIN
            pkg_billing.apply_payment(
                p_invoice_id => ut_estate_fixture.c_invoice_issued,
                p_amount     => 0,
                p_method     => 'CARD'
            );
            ut.fail('Expected ORA-02290 from ck_payments_amount');
        EXCEPTION
            WHEN OTHERS THEN
                -- WHEN OTHERS ends in RAISE, so the constraint error is not
                -- translated into an estate code.
                ut.expect(SQLCODE).to_equal(-2290);
        END;
    END payment_zero_amount_raises;

    PROCEDURE payment_null_amount_raises IS
    BEGIN
        BEGIN
            pkg_billing.apply_payment(
                p_invoice_id => ut_estate_fixture.c_invoice_issued,
                p_amount     => NULL,
                p_method     => 'CARD'
            );
            ut.fail('Expected ORA-01400 because amount_paid is NOT NULL');
        EXCEPTION
            WHEN OTHERS THEN
                ut.expect(SQLCODE).to_equal(-1400);
        END;
    END payment_null_amount_raises;

    PROCEDURE payment_writes_audit_row IS
        l_action  audit_log.action_code%TYPE;
        l_payload VARCHAR2(4000);
    BEGIN
        pkg_billing.apply_payment(
            p_invoice_id => ut_estate_fixture.c_invoice_issued,
            p_amount     => 21.01,
            p_method     => 'CARD'
        );

        SELECT action_code, TO_CHAR(payload)
        INTO l_action, l_payload
        FROM audit_log
        WHERE entity_id = ut_estate_fixture.c_invoice_issued
          AND action_code = 'PAYMENT'
          AND audit_id >= 100000;

        ut.expect(l_action).to_equal('PAYMENT');
        -- Pattern matched rather than compared exactly: the payload is built
        -- with TO_CHAR(p_amount) and no format model, so the exact text depends
        -- on NLS settings. The migration should pin a format model here.
        ut.expect(l_payload).to_be_like('paid=%21%01%method=CARD');
    END payment_writes_audit_row;

    ---------------------------------------------------------------------------
    -- rebuild_invoice_totals
    ---------------------------------------------------------------------------

    PROCEDURE rebuild_sums_and_taxes_lines IS
        l_total     invoices.invoice_total%TYPE;
        l_tax_total invoices.tax_total%TYPE;
        l_line_tax  invoice_lines.tax_amount%TYPE;
    BEGIN
        -- Invoice 94003 has three lines: 100.00, NULL and 0.00.
        pkg_billing.rebuild_invoice_totals(ut_estate_fixture.c_invoice_draft);

        SELECT invoice_total, tax_total
        INTO l_total, l_tax_total
        FROM invoices
        WHERE invoice_id = ut_estate_fixture.c_invoice_draft;

        SELECT tax_amount
        INTO l_line_tax
        FROM invoice_lines
        WHERE invoice_line_id = ut_estate_fixture.c_inv_line_full;

        ut.expect(l_total).to_equal(100.00);
        ut.expect(l_tax_total).to_equal(8.25);
        ut.expect(l_line_tax).to_equal(8.25);
    END rebuild_sums_and_taxes_lines;

    PROCEDURE rebuild_null_line_is_zero IS
        l_null_line_tax invoice_lines.tax_amount%TYPE;
        l_zero_line_tax invoice_lines.tax_amount%TYPE;
    BEGIN
        pkg_billing.rebuild_invoice_totals(ut_estate_fixture.c_invoice_draft);

        SELECT tax_amount
        INTO l_null_line_tax
        FROM invoice_lines
        WHERE invoice_line_id = ut_estate_fixture.c_inv_line_null_amt;

        SELECT tax_amount
        INTO l_zero_line_tax
        FROM invoice_lines
        WHERE invoice_line_id = ut_estate_fixture.c_inv_line_zero_amt;

        -- NVL in the dynamic SELECT and NVL again in the loop, so a NULL amount
        -- becomes a stored zero tax rather than a NULL tax.
        ut.expect(l_null_line_tax).to_equal(0);
        ut.expect(l_zero_line_tax).to_equal(0);
    END rebuild_null_line_is_zero;

    PROCEDURE rebuild_without_lines_zeroes IS
        l_total     invoices.invoice_total%TYPE;
        l_tax_total invoices.tax_total%TYPE;
    BEGIN
        -- Invoice 94001 has no invoice_lines rows but does carry a total of
        -- 31.01 and 10.00 of payments.
        pkg_billing.rebuild_invoice_totals(ut_estate_fixture.c_invoice_issued);

        SELECT invoice_total, tax_total
        INTO l_total, l_tax_total
        FROM invoices
        WHERE invoice_id = ut_estate_fixture.c_invoice_issued;

        -- Destructive by design in the source: no lines means the invoice total
        -- is reset to zero. Pinned because it is easy to "fix" during a
        -- conversion and then diverge from production.
        ut.expect(l_total).to_equal(0);
        ut.expect(l_tax_total).to_equal(0);
    END rebuild_without_lines_zeroes;

    PROCEDURE rebuild_reports_issued_label IS
        l_invoice_id invoices.invoice_id%TYPE;
        l_output     VARCHAR2(32767);
    BEGIN
        pkg_billing.issue_invoice(
            p_order_id   => ut_estate_fixture.c_order_billing,
            p_invoice_id => l_invoice_id
        );

        ut_estate_fixture.start_output_capture;
        pkg_billing.rebuild_invoice_totals(l_invoice_id);
        l_output := ut_estate_fixture.captured_output;

        -- g_run_label is package state written by issue_invoice and read by
        -- rebuild_invoice_totals. Nothing passes it between the two calls.
        ut.expect(l_output).to_be_like(
            '%rebuilt INV-' || TO_CHAR(l_invoice_id) || ' total=%'
        );
    END rebuild_reports_issued_label;

    PROCEDURE rebuild_label_survives_rollback IS
        l_invoice_id invoices.invoice_id%TYPE;
        l_output     VARCHAR2(32767);
    BEGIN
        pkg_billing.issue_invoice(
            p_order_id   => ut_estate_fixture.c_order_billing,
            p_invoice_id => l_invoice_id
        );

        ROLLBACK;

        ut_estate_fixture.start_output_capture;
        pkg_billing.rebuild_invoice_totals(ut_estate_fixture.c_invoice_draft);
        l_output := ut_estate_fixture.captured_output;

        -- Package state is session scoped, not transaction scoped, so the label
        -- still names an invoice that no longer exists.
        ut.expect(l_output).to_be_like(
            '%rebuilt INV-' || TO_CHAR(l_invoice_id) || '%'
        );

        -- This test manages its own transaction, so undo the rebuild too.
        ROLLBACK;
        ut_estate_fixture.purge_audit_rows(l_invoice_id);
    END rebuild_label_survives_rollback;

END ut_pkg_billing;
/
