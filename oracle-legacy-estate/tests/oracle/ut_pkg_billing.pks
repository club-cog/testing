CREATE OR REPLACE PACKAGE ut_pkg_billing AS
    --%suite(pkg_billing characterization)
    --%suitepath(estate.oracle)
    --%displayname(Characterization of pkg_billing on Oracle 19c)
    --%rollback(auto)

    --%beforeall
    PROCEDURE suite_setup;

    --%beforeeach
    PROCEDURE test_setup;

    --%aftereach
    PROCEDURE test_teardown;

    --%afterall
    PROCEDURE suite_teardown;

    -- issue_invoice

    --%test(issue_invoice creates an ISSUED invoice carrying the order total)
    PROCEDURE issue_creates_issued_invoice;

    --%test(issue_invoice numbers the invoice INV- followed by the sequence value)
    PROCEDURE issue_numbers_from_sequence;

    --%test(issue_invoice stores an unrounded tax that the column rounds to 2 decimals)
    PROCEDURE issue_rounds_tax_on_insert;

    --%test(issue_invoice sets due_on to 30 days after issued_on, time of day included)
    PROCEDURE issue_due_on_is_plus_30_days;

    --%test(issue_invoice writes an ISSUED audit row naming the invoice)
    PROCEDURE issue_writes_audit_row;

    --%test(issue_invoice audit row survives a rollback of the invoice itself)
    --%rollback(manual)
    PROCEDURE issue_audit_row_is_committed;

    --%test(issue_invoice reports ORA-20911 for an order that does not exist)
    PROCEDURE issue_unknown_order_raises;

    --%test(issue_invoice reports ORA-20911 for a second invoice on the same order)
    PROCEDURE issue_second_invoice_raises;

    -- apply_payment

    --%test(apply_payment marks the invoice PAID once the captured total covers it)
    PROCEDURE payment_full_marks_paid;

    --%test(apply_payment marks the invoice PARTIAL while a balance remains)
    PROCEDURE payment_short_marks_partial;

    --%test(apply_payment ignores REVERSED payments when totalling what was paid)
    PROCEDURE payment_ignores_reversed;

    --%test(apply_payment stores UNKNOWN for a NULL payment method)
    PROCEDURE payment_null_method_is_unknown;

    --%test(apply_payment stores UNKNOWN for an empty string payment method)
    PROCEDURE payment_empty_method_is_unknown;

    --%test(apply_payment on a VOID invoice records PENDING and overwrites VOID)
    PROCEDURE payment_on_void_invoice;

    --%test(apply_payment raises ORA-20912 for an invoice that does not exist)
    PROCEDURE payment_unknown_invoice_raises;

    --%test(apply_payment raises the check constraint error for a zero amount)
    PROCEDURE payment_zero_amount_raises;

    --%test(apply_payment raises the NOT NULL error for a NULL amount)
    PROCEDURE payment_null_amount_raises;

    --%test(apply_payment writes a PAYMENT audit row with amount and method)
    PROCEDURE payment_writes_audit_row;

    -- rebuild_invoice_totals

    --%test(rebuild_invoice_totals sums the lines and taxes each line at 8.25 percent)
    PROCEDURE rebuild_sums_and_taxes_lines;

    --%test(rebuild_invoice_totals treats a NULL line amount as zero)
    PROCEDURE rebuild_null_line_is_zero;

    --%test(rebuild_invoice_totals zeroes the totals of an invoice with no lines)
    PROCEDURE rebuild_without_lines_zeroes;

    --%test(rebuild_invoice_totals reports the label left by issue_invoice)
    PROCEDURE rebuild_reports_issued_label;

    --%test(the package label survives a rolled back issue_invoice in the same session)
    --%rollback(manual)
    PROCEDURE rebuild_label_survives_rollback;
END ut_pkg_billing;
/
