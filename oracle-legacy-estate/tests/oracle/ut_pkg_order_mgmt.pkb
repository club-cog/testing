CREATE OR REPLACE PACKAGE BODY ut_pkg_order_mgmt AS

    -- Every test runs inside the utPLSQL transaction and is rolled back
    -- afterwards, so the fixture rows loaded by tests/fixtures/*.sql stay intact.
    -- The one exception in this estate is pkg_billing.write_billing_log, which
    -- commits autonomously; pkg_order_mgmt never calls it.

    g_expected_customer_count PLS_INTEGER;

    PROCEDURE suite_setup IS
    BEGIN
        -- Guard against running the suite on an unseeded schema. A missing
        -- fixture would otherwise show up as a pile of confusing failures.
        SELECT COUNT(*)
        INTO g_expected_customer_count
        FROM customers
        WHERE customer_id BETWEEN ut_estate_fixture.c_fixture_low
                              AND ut_estate_fixture.c_fixture_high;

        IF g_expected_customer_count <> 12 THEN
            RAISE_APPLICATION_ERROR(
                -20001,
                'Fixture not loaded: expected 12 fixture customers, found '
                || g_expected_customer_count
            );
        END IF;

        DBMS_OUTPUT.ENABLE(1000000);
    END suite_setup;

    PROCEDURE suite_teardown IS
    BEGIN
        -- Nothing to undo. Kept so that the annotation pair is explicit and any
        -- future manual cleanup has a home.
        NULL;
    END suite_teardown;

    PROCEDURE test_setup IS
    BEGIN
        ut_estate_fixture.start_output_capture;
    END test_setup;

    ---------------------------------------------------------------------------
    -- create_order
    ---------------------------------------------------------------------------

    PROCEDURE create_null_requester_is_open IS
        l_order_id  orders.order_id%TYPE;
        l_status    orders.order_status%TYPE;
        l_requester orders.requested_by%TYPE;
        l_total     orders.total_amount%TYPE;
    BEGIN
        pkg_order_mgmt.create_order(
            p_order_number => 'UT-OM-01',
            p_customer_id  => ut_estate_fixture.c_root_customer,
            p_requested_by => NULL,
            p_order_id     => l_order_id
        );

        SELECT order_status, requested_by, total_amount
        INTO l_status, l_requester, l_total
        FROM orders
        WHERE order_id = l_order_id;

        ut.expect(l_order_id).to_be_not_null();
        ut.expect(l_status).to_equal('OPEN');
        ut.expect(l_requester).to_equal('BATCH');
        -- Written by the BEFORE INSERT trigger, not by the package.
        ut.expect(l_total).to_equal(0);
    END create_null_requester_is_open;

    PROCEDURE create_named_requester_is_held IS
        l_order_id  orders.order_id%TYPE;
        l_status    orders.order_status%TYPE;
        l_requester orders.requested_by%TYPE;
    BEGIN
        pkg_order_mgmt.create_order(
            p_order_number => 'UT-OM-02',
            p_customer_id  => ut_estate_fixture.c_root_customer,
            p_requested_by => 'ANNA-FIXTURE',
            p_order_id     => l_order_id
        );

        SELECT order_status, requested_by
        INTO l_status, l_requester
        FROM orders
        WHERE order_id = l_order_id;

        ut.expect(l_status).to_equal('HELD');
        ut.expect(l_requester).to_equal('ANNA-FIXTURE');
    END create_named_requester_is_held;

    PROCEDURE create_literal_batch_is_open IS
        l_order_id orders.order_id%TYPE;
        l_status   orders.order_status%TYPE;
    BEGIN
        pkg_order_mgmt.create_order(
            p_order_number => 'UT-OM-03',
            p_customer_id  => ut_estate_fixture.c_root_customer,
            p_requested_by => 'BATCH',
            p_order_id     => l_order_id
        );

        SELECT order_status
        INTO l_status
        FROM orders
        WHERE order_id = l_order_id;

        ut.expect(l_status).to_equal('OPEN');
    END create_literal_batch_is_open;

    PROCEDURE create_empty_requester_is_batch IS
        l_order_id  orders.order_id%TYPE;
        l_status    orders.order_status%TYPE;
        l_requester orders.requested_by%TYPE;
    BEGIN
        -- Oracle folds the zero length string to NULL before NVL and NVL2 see
        -- it, so this behaves exactly like the NULL case above. PostgreSQL will
        -- not: '' is a value there, so the DECODE falls through to HELD and
        -- requested_by is stored as an empty string.
        pkg_order_mgmt.create_order(
            p_order_number => 'UT-OM-04',
            p_customer_id  => ut_estate_fixture.c_root_customer,
            p_requested_by => '',
            p_order_id     => l_order_id
        );

        SELECT order_status, requested_by
        INTO l_status, l_requester
        FROM orders
        WHERE order_id = l_order_id;

        ut.expect(l_status).to_equal('OPEN');
        ut.expect(l_requester).to_equal('BATCH');
    END create_empty_requester_is_batch;

    PROCEDURE create_publishes_package_state IS
        l_order_id orders.order_id%TYPE;
    BEGIN
        pkg_order_mgmt.create_order(
            p_order_number => 'UT-OM-05',
            p_customer_id  => ut_estate_fixture.c_region_south,
            p_requested_by => NULL,
            p_order_id     => l_order_id
        );

        -- g_last_order_id is set by the dynamic SQL lookup, not by RETURNING,
        -- and it survives after the call returns.
        ut.expect(pkg_order_mgmt.g_last_order_id).to_equal(l_order_id);
    END create_publishes_package_state;

    PROCEDURE create_duplicate_raises_20901 IS
        l_order_id orders.order_id%TYPE;
    BEGIN
        pkg_order_mgmt.create_order(
            p_order_number => 'UT-OM-06',
            p_customer_id  => ut_estate_fixture.c_root_customer,
            p_requested_by => NULL,
            p_order_id     => l_order_id
        );

        BEGIN
            pkg_order_mgmt.create_order(
                p_order_number => 'UT-OM-06',
                p_customer_id  => ut_estate_fixture.c_root_customer,
                p_requested_by => NULL,
                p_order_id     => l_order_id
            );
            ut.fail('Expected ORA-20901 for a duplicate order number');
        EXCEPTION
            WHEN OTHERS THEN
                ut.expect(SQLCODE).to_equal(-20901);
                ut.expect(SQLERRM).to_be_like('%Order number already exists%');
        END;
    END create_duplicate_raises_20901;

    PROCEDURE create_duplicate_leaves_no_row IS
        l_order_id   orders.order_id%TYPE;
        l_row_count  PLS_INTEGER;
    BEGIN
        pkg_order_mgmt.create_order(
            p_order_number => 'UT-OM-07',
            p_customer_id  => ut_estate_fixture.c_root_customer,
            p_requested_by => NULL,
            p_order_id     => l_order_id
        );

        BEGIN
            pkg_order_mgmt.create_order(
                p_order_number => 'UT-OM-07',
                p_customer_id  => ut_estate_fixture.c_region_north,
                p_requested_by => NULL,
                p_order_id     => l_order_id
            );
        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;

        SELECT COUNT(*)
        INTO l_row_count
        FROM orders
        WHERE order_number = 'UT-OM-07';

        -- ROLLBACK TO before_order discards the failed insert only. The first
        -- order is still there, which is what the SAVEPOINT is for.
        ut.expect(l_row_count).to_equal(1);
    END create_duplicate_leaves_no_row;

    PROCEDURE create_failure_keeps_state IS
        l_order_id     orders.order_id%TYPE;
        l_state_before orders.order_id%TYPE;
    BEGIN
        pkg_order_mgmt.create_order(
            p_order_number => 'UT-OM-08',
            p_customer_id  => ut_estate_fixture.c_root_customer,
            p_requested_by => NULL,
            p_order_id     => l_order_id
        );
        l_state_before := pkg_order_mgmt.g_last_order_id;

        BEGIN
            pkg_order_mgmt.create_order(
                p_order_number => 'UT-OM-08',
                p_customer_id  => ut_estate_fixture.c_root_customer,
                p_requested_by => NULL,
                p_order_id     => l_order_id
            );
        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;

        -- Package state is not part of the transaction, so the rollback inside
        -- the exception handler does not reset it.
        ut.expect(pkg_order_mgmt.g_last_order_id).to_equal(l_state_before);
    END create_failure_keeps_state;

    PROCEDURE create_untrimmed_number_fails IS
        l_order_id  orders.order_id%TYPE;
        l_row_count PLS_INTEGER;
    BEGIN
        -- The BEFORE INSERT trigger stores 'UT-OM-09', then the procedure looks
        -- the row up by the raw parameter value and finds nothing.
        BEGIN
            pkg_order_mgmt.create_order(
                p_order_number => '  ut-om-09  ',
                p_customer_id  => ut_estate_fixture.c_root_customer,
                p_requested_by => NULL,
                p_order_id     => l_order_id
            );
            ut.fail('Expected NO_DATA_FOUND from the dynamic SQL lookup');
        EXCEPTION
            WHEN OTHERS THEN
                -- Re-raised unchanged by the WHEN OTHERS handler, so the caller
                -- sees ORA-01403 with SQLCODE 100 rather than an estate code.
                ut.expect(SQLCODE).to_equal(100);
        END;

        SELECT COUNT(*)
        INTO l_row_count
        FROM orders
        WHERE order_number = 'UT-OM-09';

        ut.expect(l_row_count).to_equal(0);
    END create_untrimmed_number_fails;

    ---------------------------------------------------------------------------
    -- add_order_line
    ---------------------------------------------------------------------------

    PROCEDURE add_line_numbers_sequentially IS
        l_order_id  orders.order_id%TYPE;
        l_lines     SYS_REFCURSOR;
        l_expected  SYS_REFCURSOR;
    BEGIN
        pkg_order_mgmt.create_order(
            p_order_number => 'UT-OM-10',
            p_customer_id  => ut_estate_fixture.c_root_customer,
            p_requested_by => NULL,
            p_order_id     => l_order_id
        );

        pkg_order_mgmt.add_order_line(
            p_order_id   => l_order_id,
            p_product_id => ut_estate_fixture.c_product_widget,
            p_quantity   => 1,
            p_unit_price => 10.00
        );
        pkg_order_mgmt.add_order_line(
            p_order_id   => l_order_id,
            p_product_id => ut_estate_fixture.c_product_gadget,
            p_quantity   => 2,
            p_unit_price => 19.99
        );

        OPEN l_lines FOR
            SELECT line_number, product_id, quantity, extended_amount
            FROM order_lines
            WHERE order_id = l_order_id
            ORDER BY line_number;

        OPEN l_expected FOR
            SELECT 1 AS line_number,
                   ut_estate_fixture.c_product_widget AS product_id,
                   1 AS quantity,
                   10.00 AS extended_amount
            FROM DUAL
            UNION ALL
            SELECT 2, ut_estate_fixture.c_product_gadget, 2, 39.98 FROM DUAL;

        ut.expect(l_lines).to_equal(l_expected);
    END add_line_numbers_sequentially;

    PROCEDURE add_line_computes_extended IS
        l_order_id  orders.order_id%TYPE;
        l_extended  order_lines.extended_amount%TYPE;
        l_discount  order_lines.discount_rate%TYPE;
    BEGIN
        pkg_order_mgmt.create_order(
            p_order_number => 'UT-OM-11',
            p_customer_id  => ut_estate_fixture.c_root_customer,
            p_requested_by => NULL,
            p_order_id     => l_order_id
        );

        pkg_order_mgmt.add_order_line(
            p_order_id   => l_order_id,
            p_product_id => ut_estate_fixture.c_product_gadget,
            p_quantity   => 3,
            p_unit_price => 19.99
        );

        SELECT extended_amount, discount_rate
        INTO l_extended, l_discount
        FROM order_lines
        WHERE order_id = l_order_id
          AND line_number = 1;

        ut.expect(l_extended).to_equal(59.97);
        -- The procedure always writes a zero discount rate, ignoring price_tiers.
        ut.expect(l_discount).to_equal(0);
    END add_line_computes_extended;

    PROCEDURE add_line_null_quantity_is_one IS
        l_order_id  orders.order_id%TYPE;
        l_quantity  order_lines.quantity%TYPE;
        l_extended  order_lines.extended_amount%TYPE;
    BEGIN
        pkg_order_mgmt.create_order(
            p_order_number => 'UT-OM-12',
            p_customer_id  => ut_estate_fixture.c_root_customer,
            p_requested_by => NULL,
            p_order_id     => l_order_id
        );

        pkg_order_mgmt.add_order_line(
            p_order_id   => l_order_id,
            p_product_id => ut_estate_fixture.c_product_widget,
            p_quantity   => NULL,
            p_unit_price => 12.34
        );

        SELECT quantity, extended_amount
        INTO l_quantity, l_extended
        FROM order_lines
        WHERE order_id = l_order_id
          AND line_number = 1;

        ut.expect(l_quantity).to_equal(1);
        ut.expect(l_extended).to_equal(12.34);
    END add_line_null_quantity_is_one;

    PROCEDURE add_line_null_price_raises IS
        l_order_id orders.order_id%TYPE;
    BEGIN
        pkg_order_mgmt.create_order(
            p_order_number => 'UT-OM-13',
            p_customer_id  => ut_estate_fixture.c_root_customer,
            p_requested_by => NULL,
            p_order_id     => l_order_id
        );

        BEGIN
            pkg_order_mgmt.add_order_line(
                p_order_id   => l_order_id,
                p_product_id => ut_estate_fixture.c_product_widget,
                p_quantity   => 2,
                p_unit_price => NULL
            );
            ut.fail('Expected ORA-01400 because unit_price is NOT NULL');
        EXCEPTION
            WHEN OTHERS THEN
                -- add_order_line has no exception handler, so the storage layer
                -- error reaches the caller unchanged.
                ut.expect(SQLCODE).to_equal(-1400);
        END;
    END add_line_null_price_raises;

    PROCEDURE add_line_sets_order_totals IS
        l_order_id orders.order_id%TYPE;
        l_subtotal orders.subtotal_amount%TYPE;
        l_discount orders.discount_amount%TYPE;
        l_tax      orders.tax_amount%TYPE;
        l_total    orders.total_amount%TYPE;
    BEGIN
        pkg_order_mgmt.create_order(
            p_order_number => 'UT-OM-14',
            p_customer_id  => ut_estate_fixture.c_root_customer,
            p_requested_by => NULL,
            p_order_id     => l_order_id
        );

        pkg_order_mgmt.add_order_line(
            p_order_id   => l_order_id,
            p_product_id => ut_estate_fixture.c_product_gadget,
            p_quantity   => 3,
            p_unit_price => 19.99
        );

        SELECT subtotal_amount, discount_amount, tax_amount, total_amount
        INTO l_subtotal, l_discount, l_tax, l_total
        FROM orders
        WHERE order_id = l_order_id;

        -- The AFTER INSERT trigger sets subtotal and total with no tax, then
        -- refresh_order_total overwrites both. The tax visible here is
        -- ROUND(59.97 * 0.0825, 2) = ROUND(4.947525, 2).
        ut.expect(l_subtotal).to_equal(59.97);
        ut.expect(l_discount).to_equal(0);
        ut.expect(l_tax).to_equal(4.95);
        ut.expect(l_total).to_equal(64.92);
    END add_line_sets_order_totals;

    ---------------------------------------------------------------------------
    -- refresh_order_total
    ---------------------------------------------------------------------------

    PROCEDURE refresh_rounds_tax_half_up IS
        l_tax   orders.tax_amount%TYPE;
        l_total orders.total_amount%TYPE;
    BEGIN
        -- 10.00 * 0.0825 = 0.825 exactly, which is the half way case.
        UPDATE order_lines
        SET unit_price = 10.00,
            quantity = 1,
            extended_amount = 10.00
        WHERE order_id = ut_estate_fixture.c_order_page_2
          AND line_number = 1;

        pkg_order_mgmt.refresh_order_total(ut_estate_fixture.c_order_page_2);

        SELECT tax_amount, total_amount
        INTO l_tax, l_total
        FROM orders
        WHERE order_id = ut_estate_fixture.c_order_page_2;

        ut.expect(l_tax).to_equal(0.83);
        ut.expect(l_total).to_equal(10.83);
    END refresh_rounds_tax_half_up;

    PROCEDURE refresh_rounds_discount_first IS
        l_subtotal orders.subtotal_amount%TYPE;
        l_discount orders.discount_amount%TYPE;
        l_tax      orders.tax_amount%TYPE;
        l_total    orders.total_amount%TYPE;
    BEGIN
        -- 59.97 * 33.33 / 100 = 19.988001. The local variable is declared as
        -- orders.discount_amount%TYPE, that is NUMBER(14, 2), so PL/SQL rounds
        -- the value to 19.99 on assignment and the tax is computed from the
        -- rounded figure, not from 19.988001.
        UPDATE order_lines
        SET discount_rate = 33.33
        WHERE order_id = ut_estate_fixture.c_order_page_3
          AND line_number = 1;

        pkg_order_mgmt.refresh_order_total(ut_estate_fixture.c_order_page_3);

        SELECT subtotal_amount, discount_amount, tax_amount, total_amount
        INTO l_subtotal, l_discount, l_tax, l_total
        FROM orders
        WHERE order_id = ut_estate_fixture.c_order_page_3;

        ut.expect(l_subtotal).to_equal(59.97);
        ut.expect(l_discount).to_equal(19.99);
        -- ROUND((59.97 - 19.99) * 0.0825, 2) = ROUND(3.29835, 2)
        ut.expect(l_tax).to_equal(3.30);
        ut.expect(l_total).to_equal(43.28);
    END refresh_rounds_discount_first;

    PROCEDURE refresh_order_without_lines IS
        l_subtotal orders.subtotal_amount%TYPE;
        l_discount orders.discount_amount%TYPE;
        l_tax      orders.tax_amount%TYPE;
        l_total    orders.total_amount%TYPE;
    BEGIN
        pkg_order_mgmt.refresh_order_total(ut_estate_fixture.c_order_page_1);

        SELECT subtotal_amount, discount_amount, tax_amount, total_amount
        INTO l_subtotal, l_discount, l_tax, l_total
        FROM orders
        WHERE order_id = ut_estate_fixture.c_order_page_1;

        ut.expect(l_subtotal).to_equal(0);
        ut.expect(l_discount).to_equal(0);
        ut.expect(l_tax).to_equal(0);
        ut.expect(l_total).to_equal(0);
    END refresh_order_without_lines;

    PROCEDURE refresh_unknown_order_is_silent IS
        l_row_count PLS_INTEGER;
    BEGIN
        -- The aggregate query returns a row of zeros for an unknown order and
        -- the UPDATE matches nothing, so the call succeeds and changes nothing.
        pkg_order_mgmt.refresh_order_total(ut_estate_fixture.c_missing_order);

        SELECT COUNT(*)
        INTO l_row_count
        FROM orders
        WHERE order_id = ut_estate_fixture.c_missing_order;

        ut.expect(l_row_count).to_equal(0);
    END refresh_unknown_order_is_silent;

    ---------------------------------------------------------------------------
    -- list_customer_orders
    ---------------------------------------------------------------------------

    PROCEDURE list_first_page IS
        l_actual   SYS_REFCURSOR;
        l_expected SYS_REFCURSOR;
    BEGIN
        pkg_order_mgmt.list_customer_orders(
            p_customer_id => ut_estate_fixture.c_root_customer,
            p_page_number => 1,
            p_page_size   => 2,
            p_result      => l_actual
        );

        OPEN l_expected FOR
            SELECT ut_estate_fixture.c_order_page_5 AS order_id,
                   'PO-PAGE-5' AS order_number
            FROM DUAL
            UNION ALL
            SELECT ut_estate_fixture.c_order_page_4, 'PO-PAGE-4' FROM DUAL;

        ut.expect(l_actual).to_equal(l_expected).include('ORDER_ID,ORDER_NUMBER');
    END list_first_page;

    PROCEDURE list_second_page IS
        l_actual   SYS_REFCURSOR;
        l_expected SYS_REFCURSOR;
    BEGIN
        pkg_order_mgmt.list_customer_orders(
            p_customer_id => ut_estate_fixture.c_root_customer,
            p_page_number => 2,
            p_page_size   => 2,
            p_result      => l_actual
        );

        OPEN l_expected FOR
            SELECT ut_estate_fixture.c_order_page_3 AS order_id,
                   'PO-PAGE-3' AS order_number
            FROM DUAL
            UNION ALL
            SELECT ut_estate_fixture.c_order_page_2, 'PO-PAGE-2' FROM DUAL;

        ut.expect(l_actual).to_equal(l_expected).include('ORDER_ID,ORDER_NUMBER');
    END list_second_page;

    PROCEDURE list_partial_last_page IS
        l_actual   SYS_REFCURSOR;
        l_expected SYS_REFCURSOR;
    BEGIN
        pkg_order_mgmt.list_customer_orders(
            p_customer_id => ut_estate_fixture.c_root_customer,
            p_page_number => 3,
            p_page_size   => 2,
            p_result      => l_actual
        );

        OPEN l_expected FOR
            SELECT ut_estate_fixture.c_order_page_1 AS order_id,
                   'PO-PAGE-1' AS order_number
            FROM DUAL;

        ut.expect(l_actual).to_equal(l_expected).include('ORDER_ID,ORDER_NUMBER');
    END list_partial_last_page;

    PROCEDURE list_null_paging_defaults IS
        l_actual   SYS_REFCURSOR;
        l_expected SYS_REFCURSOR;
    BEGIN
        pkg_order_mgmt.list_customer_orders(
            p_customer_id => ut_estate_fixture.c_root_customer,
            p_page_number => NULL,
            p_page_size   => NULL,
            p_result      => l_actual
        );

        -- Rows 1 to 25 of the ordered_at DESC ordering, so all five fixture
        -- orders in newest first order.
        OPEN l_expected FOR
            SELECT ut_estate_fixture.c_order_page_5 AS order_id FROM DUAL
            UNION ALL SELECT ut_estate_fixture.c_order_page_4 FROM DUAL
            UNION ALL SELECT ut_estate_fixture.c_order_page_3 FROM DUAL
            UNION ALL SELECT ut_estate_fixture.c_order_page_2 FROM DUAL
            UNION ALL SELECT ut_estate_fixture.c_order_page_1 FROM DUAL;

        ut.expect(l_actual).to_equal(l_expected).include('ORDER_ID');
    END list_null_paging_defaults;

    PROCEDURE list_zero_page_size IS
        l_actual SYS_REFCURSOR;
    BEGIN
        -- l_end_row becomes 0, so the inner predicate is ROWNUM <= 0 and no row
        -- can ever qualify.
        pkg_order_mgmt.list_customer_orders(
            p_customer_id => ut_estate_fixture.c_root_customer,
            p_page_number => 1,
            p_page_size   => 0,
            p_result      => l_actual
        );

        ut.expect(l_actual).to_be_empty();
    END list_zero_page_size;

    PROCEDURE list_unknown_customer IS
        l_actual SYS_REFCURSOR;
    BEGIN
        pkg_order_mgmt.list_customer_orders(
            p_customer_id => ut_estate_fixture.c_missing_customer,
            p_page_number => 1,
            p_page_size   => 10,
            p_result      => l_actual
        );

        ut.expect(l_actual).to_be_empty();
    END list_unknown_customer;

    ---------------------------------------------------------------------------
    -- load_order_totals
    ---------------------------------------------------------------------------

    PROCEDURE load_totals_populates_gtt IS
        l_actual   SYS_REFCURSOR;
        l_expected SYS_REFCURSOR;
    BEGIN
        pkg_order_mgmt.load_order_totals(ut_estate_fixture.c_root_customer);

        OPEN l_actual FOR
            SELECT order_id, line_count, calculated_total
            FROM gtt_order_totals
            ORDER BY order_id;

        OPEN l_expected FOR
            SELECT ut_estate_fixture.c_order_page_1 AS order_id,
                   0 AS line_count,
                   0 AS calculated_total
            FROM DUAL
            UNION ALL SELECT ut_estate_fixture.c_order_page_2, 1, 100.00 FROM DUAL
            UNION ALL SELECT ut_estate_fixture.c_order_page_3, 1, 59.97 FROM DUAL
            UNION ALL SELECT ut_estate_fixture.c_order_page_4, 1, 0 FROM DUAL
            UNION ALL SELECT ut_estate_fixture.c_order_page_5, 2, 31.01 FROM DUAL;

        ut.expect(l_actual).to_equal(l_expected);
    END load_totals_populates_gtt;

    PROCEDURE load_totals_null_total_is_zero IS
        l_calculated gtt_order_totals.calculated_total%TYPE;
    BEGIN
        -- A direct UPDATE can leave total_amount NULL: the check constraint
        -- allows it and the BEFORE INSERT trigger only fires on insert.
        UPDATE orders
        SET total_amount = NULL
        WHERE order_id = ut_estate_fixture.c_order_page_2;

        pkg_order_mgmt.load_order_totals(ut_estate_fixture.c_root_customer);

        SELECT calculated_total
        INTO l_calculated
        FROM gtt_order_totals
        WHERE order_id = ut_estate_fixture.c_order_page_2;

        ut.expect(l_calculated).to_equal(0);
    END load_totals_null_total_is_zero;

    PROCEDURE load_totals_clears_previous IS
        l_stale_rows PLS_INTEGER;
    BEGIN
        INSERT INTO gtt_order_totals (order_id, line_count, calculated_total)
        VALUES (ut_estate_fixture.c_missing_order, 99, 999.99);

        pkg_order_mgmt.load_order_totals(ut_estate_fixture.c_root_customer);

        SELECT COUNT(*)
        INTO l_stale_rows
        FROM gtt_order_totals
        WHERE order_id = ut_estate_fixture.c_missing_order;

        ut.expect(l_stale_rows).to_equal(0);
    END load_totals_clears_previous;

    PROCEDURE load_totals_unknown_customer IS
        l_row_count PLS_INTEGER;
    BEGIN
        pkg_order_mgmt.load_order_totals(ut_estate_fixture.c_missing_customer);

        SELECT COUNT(*)
        INTO l_row_count
        FROM gtt_order_totals;

        -- BULK COLLECT into an empty collection, FORALL over an empty range and
        -- no exception. The procedure reports success for an unknown customer.
        ut.expect(l_row_count).to_equal(0);
    END load_totals_unknown_customer;

    ---------------------------------------------------------------------------
    -- summarize_order
    ---------------------------------------------------------------------------

    PROCEDURE summarize_reports_line_count IS
        l_output VARCHAR2(32767);
    BEGIN
        pkg_order_mgmt.summarize_order(ut_estate_fixture.c_order_page_5);
        l_output := ut_estate_fixture.captured_output;

        -- The REVERSE loop ends at 1, so the marker always reports LINE-1.
        ut.expect(l_output).to_be_like('%lines=2 marker=LINE-1%');
    END summarize_reports_line_count;

    PROCEDURE summarize_order_without_invoice IS
        l_output VARCHAR2(32767);
    BEGIN
        pkg_order_mgmt.summarize_order(ut_estate_fixture.c_order_billing);
        l_output := ut_estate_fixture.captured_output;

        -- The legacy (+) outer join keeps the order row even with no invoice.
        ut.expect(l_output).to_be_like(
            '%order=' || ut_estate_fixture.c_order_billing || ' invoice=NONE%'
        );
        ut.expect(l_output).to_be_like('%lines=1 marker=LINE-1%');
    END summarize_order_without_invoice;

    PROCEDURE summarize_order_with_invoice IS
        l_output VARCHAR2(32767);
    BEGIN
        pkg_order_mgmt.summarize_order(ut_estate_fixture.c_order_page_5);
        l_output := ut_estate_fixture.captured_output;

        ut.expect(l_output).to_be_like(
            '%invoice=' || ut_estate_fixture.c_invoice_issued || '%'
        );
    END summarize_order_with_invoice;

    ---------------------------------------------------------------------------
    -- trigger maintained values
    ---------------------------------------------------------------------------

    PROCEDURE trigger_normalizes_order_number IS
        l_order_id     orders.order_id%TYPE;
        l_order_number orders.order_number%TYPE;
        l_status       orders.order_status%TYPE;
        l_total        orders.total_amount%TYPE;
    BEGIN
        INSERT INTO orders (order_number, customer_id, order_status, total_amount)
        VALUES ('  ut-trigger-1  ', ut_estate_fixture.c_root_customer, NULL, NULL)
        RETURNING order_id, order_number, order_status, total_amount
        INTO l_order_id, l_order_number, l_status, l_total;

        -- Three separate trigger behaviours: sequence key, normalized number,
        -- and the NVL defaults for status and total.
        ut.expect(l_order_id).to_be_not_null();
        ut.expect(l_order_number).to_equal('UT-TRIGGER-1');
        ut.expect(l_status).to_equal('OPEN');
        ut.expect(l_total).to_equal(0);
    END trigger_normalizes_order_number;

    PROCEDURE trigger_leaves_extended_amount IS
        l_extended order_lines.extended_amount%TYPE;
        l_subtotal orders.subtotal_amount%TYPE;
    BEGIN
        UPDATE order_lines
        SET quantity = 10
        WHERE order_id = ut_estate_fixture.c_order_page_3
          AND line_number = 1;

        SELECT extended_amount
        INTO l_extended
        FROM order_lines
        WHERE order_id = ut_estate_fixture.c_order_page_3
          AND line_number = 1;

        SELECT subtotal_amount
        INTO l_subtotal
        FROM orders
        WHERE order_id = ut_estate_fixture.c_order_page_3;

        -- The AFTER UPDATE trigger re-sums extended_amount but nothing
        -- recalculates extended_amount itself, so a quantity change silently
        -- leaves the money columns stale.
        ut.expect(l_extended).to_equal(59.97);
        ut.expect(l_subtotal).to_equal(59.97);
    END trigger_leaves_extended_amount;

END ut_pkg_order_mgmt;
/
