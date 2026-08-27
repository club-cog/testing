CREATE OR REPLACE PACKAGE ut_estate_fixture AS
    -- Shared support code for the Oracle characterization suites.
    --
    -- It holds the fixture key constants, a DBMS_OUTPUT capture helper (three of
    -- the estate procedures report their result only through DBMS_OUTPUT), and
    -- an autonomous cleanup for audit rows that pkg_billing commits outside the
    -- test transaction.

    -- Customers
    c_root_customer      CONSTANT NUMBER := 90001;
    c_region_north       CONSTANT NUMBER := 90002;
    c_region_south       CONSTANT NUMBER := 90003;
    c_branch_n1          CONSTANT NUMBER := 90004;
    c_branch_n2          CONSTANT NUMBER := 90005;
    c_dept_n1a           CONSTANT NUMBER := 90006;
    c_team_n1a1          CONSTANT NUMBER := 90007;
    c_solo_stale         CONSTANT NUMBER := 90008;
    c_solo_recent        CONSTANT NUMBER := 90009;
    c_solo_inactive      CONSTANT NUMBER := 90010;
    c_empty_channel      CONSTANT NUMBER := 90011;
    c_mixed_case_code    CONSTANT NUMBER := 90012;
    c_missing_customer   CONSTANT NUMBER := 99901;

    -- Products
    c_product_widget     CONSTANT NUMBER := 92001;
    c_product_gadget     CONSTANT NUMBER := 92002;
    c_product_freebie    CONSTANT NUMBER := 92003;
    c_product_assembly   CONSTANT NUMBER := 92004;

    -- Orders
    c_order_recent       CONSTANT NUMBER := 93001;
    c_order_stale        CONSTANT NUMBER := 93002;
    c_order_page_1       CONSTANT NUMBER := 93003;
    c_order_page_2       CONSTANT NUMBER := 93004;
    c_order_page_3       CONSTANT NUMBER := 93005;
    c_order_page_4       CONSTANT NUMBER := 93006;
    c_order_page_5       CONSTANT NUMBER := 93007;
    c_order_boundary     CONSTANT NUMBER := 93008;
    c_order_empty_str    CONSTANT NUMBER := 93009;
    c_order_billing      CONSTANT NUMBER := 93010;
    c_missing_order      CONSTANT NUMBER := 99902;

    -- Invoices and payments
    c_invoice_issued     CONSTANT NUMBER := 94001;
    c_invoice_void       CONSTANT NUMBER := 94002;
    c_invoice_draft      CONSTANT NUMBER := 94003;
    c_inv_line_full      CONSTANT NUMBER := 94501;
    c_inv_line_null_amt  CONSTANT NUMBER := 94502;
    c_inv_line_zero_amt  CONSTANT NUMBER := 94503;
    c_missing_invoice    CONSTANT NUMBER := 99903;

    -- Fixture key band. Rows outside it belong to the host schema, not to us.
    c_fixture_low        CONSTANT NUMBER := 90000;
    c_fixture_high       CONSTANT NUMBER := 99999;

    -- Clears the DBMS_OUTPUT buffer and enables it for the current session.
    PROCEDURE start_output_capture;

    -- Returns everything written to DBMS_OUTPUT since start_output_capture,
    -- one line per CHR(10). The buffer is consumed by the call.
    FUNCTION captured_output RETURN VARCHAR2;

    -- pkg_billing.write_billing_log commits in an autonomous transaction, so the
    -- rows it writes outlive a test rollback and have to be removed explicitly.
    PROCEDURE purge_audit_rows (p_entity_id IN NUMBER);

    -- Removes every audit row a test run committed. Fixture audit keys stay
    -- below 100000, generated keys start there (see fixtures/060_align_sequences.sql).
    PROCEDURE purge_generated_audit_rows;
END ut_estate_fixture;
/
