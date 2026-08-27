CREATE OR REPLACE PACKAGE BODY ut_pkg_customer_hier AS

    TYPE t_id_flags IS TABLE OF PLS_INTEGER INDEX BY PLS_INTEGER;

    -- Collects the fixture band ids returned by find_unordered_customers into a
    -- set, so that the assertions do not depend on the row order of MINUS. The
    -- order is stable on Oracle in practice but it is not part of the contract,
    -- and PostgreSQL EXCEPT makes no ordering promise at all.
    FUNCTION unordered_ids RETURN t_id_flags IS
        l_cursor SYS_REFCURSOR;
        l_id     customers.customer_id%TYPE;
        l_code   customers.customer_code%TYPE;
        l_result t_id_flags;
    BEGIN
        pkg_customer_hier.find_unordered_customers(p_result => l_cursor);

        LOOP
            FETCH l_cursor INTO l_id, l_code;
            EXIT WHEN l_cursor%NOTFOUND;

            IF l_id BETWEEN ut_estate_fixture.c_fixture_low
                        AND ut_estate_fixture.c_fixture_high
            THEN
                l_result(l_id) := 1;
            END IF;
        END LOOP;

        CLOSE l_cursor;
        RETURN l_result;
    END unordered_ids;

    PROCEDURE suite_setup IS
        l_depth PLS_INTEGER;
    BEGIN
        SELECT MAX(LEVEL)
        INTO l_depth
        FROM customers
        START WITH customer_id = ut_estate_fixture.c_root_customer
        CONNECT BY PRIOR customer_id = parent_customer_id;

        IF NVL(l_depth, 0) <> 5 THEN
            RAISE_APPLICATION_ERROR(
                -20003,
                'Fixture not loaded: expected a 5 level hierarchy, found depth '
                || NVL(l_depth, 0)
            );
        END IF;

        DBMS_OUTPUT.ENABLE(1000000);
    END suite_setup;

    PROCEDURE test_setup IS
    BEGIN
        ut_estate_fixture.start_output_capture;
    END test_setup;

    ---------------------------------------------------------------------------
    -- descendant_count
    ---------------------------------------------------------------------------

    PROCEDURE count_includes_the_root IS
        l_count NUMBER;
    BEGIN
        l_count := pkg_customer_hier.descendant_count(
            ut_estate_fixture.c_root_customer
        );

        -- Seven rows: ROOT-CO plus the six customers below it. The name says
        -- descendants, the query counts the root as well.
        ut.expect(l_count).to_equal(7);
    END count_includes_the_root;

    PROCEDURE count_of_subtree IS
        l_count NUMBER;
    BEGIN
        l_count := pkg_customer_hier.descendant_count(
            ut_estate_fixture.c_region_north
        );

        -- REGION-NORTH, BRANCH-N1, BRANCH-N2, DEPT-N1A, TEAM-N1A1.
        ut.expect(l_count).to_equal(5);
    END count_of_subtree;

    PROCEDURE count_of_leaf_is_one IS
        l_count NUMBER;
    BEGIN
        l_count := pkg_customer_hier.descendant_count(
            ut_estate_fixture.c_team_n1a1
        );

        ut.expect(l_count).to_equal(1);
    END count_of_leaf_is_one;

    PROCEDURE count_unknown_root_is_zero IS
        l_count NUMBER;
    BEGIN
        l_count := pkg_customer_hier.descendant_count(
            ut_estate_fixture.c_missing_customer
        );

        -- COUNT(*) over an empty IN list, so no NO_DATA_FOUND and no NULL.
        ut.expect(l_count).to_equal(0);
    END count_unknown_root_is_zero;

    PROCEDURE count_null_root_is_zero IS
        l_count NUMBER;
    BEGIN
        -- START WITH customer_id = NULL selects no start row, so the walk never
        -- begins. Callers cannot distinguish this from an unknown id.
        l_count := pkg_customer_hier.descendant_count(NULL);

        ut.expect(l_count).to_equal(0);
    END count_null_root_is_zero;

    PROCEDURE count_raises_on_loop IS
        l_parent_id customers.customer_id%TYPE;
        l_child_id  customers.customer_id%TYPE;
        l_count     NUMBER;
    BEGIN
        INSERT INTO customers (customer_code, display_name, status)
        VALUES ('UT-LOOP-P', 'Loop Parent Fixture', 'A')
        RETURNING customer_id INTO l_parent_id;

        INSERT INTO customers (
            customer_code, display_name, status, parent_customer_id
        )
        VALUES ('UT-LOOP-C', 'Loop Child Fixture', 'A', l_parent_id)
        RETURNING customer_id INTO l_child_id;

        -- Close the loop. The foreign key permits it because both rows exist.
        UPDATE customers
        SET parent_customer_id = l_child_id
        WHERE customer_id = l_parent_id;

        BEGIN
            l_count := pkg_customer_hier.descendant_count(l_parent_id);
            ut.fail('Expected ORA-01436 for a CONNECT BY loop, got ' || l_count);
        EXCEPTION
            WHEN OTHERS THEN
                -- The query has no NOCYCLE, so a cyclic parent link is a hard
                -- error rather than a truncated walk.
                ut.expect(SQLCODE).to_equal(-1436);
        END;
    END count_raises_on_loop;

    ---------------------------------------------------------------------------
    -- print_tree
    ---------------------------------------------------------------------------

    PROCEDURE tree_indents_and_orders IS
        l_output   VARCHAR2(32767);
        l_expected VARCHAR2(32767);
    BEGIN
        pkg_customer_hier.print_tree(ut_estate_fixture.c_root_customer);
        l_output := ut_estate_fixture.captured_output;

        -- Depth first, siblings by customer_code, two spaces per level. Level 1
        -- has no indent at all because LPAD(' ', 0) returns NULL on Oracle and
        -- NULL || code is just code. PostgreSQL returns an empty string from
        -- lpad(' ', 0), which happens to print the same, but the two get there
        -- by different rules and any non empty pad character would diverge.
        l_expected :=
            'ROOT-CO level=1' || CHR(10)
            || '  REGION-NORTH level=2' || CHR(10)
            || '    BRANCH-N1 level=3' || CHR(10)
            || '      DEPT-N1A level=4' || CHR(10)
            || '        TEAM-N1A1 level=5' || CHR(10)
            || '    BRANCH-N2 level=3' || CHR(10)
            || '  REGION-SOUTH level=2' || CHR(10);

        ut.expect(l_output).to_equal(l_expected);
    END tree_indents_and_orders;

    PROCEDURE tree_unknown_root_is_silent IS
        l_output VARCHAR2(32767);
    BEGIN
        pkg_customer_hier.print_tree(ut_estate_fixture.c_missing_customer);
        l_output := ut_estate_fixture.captured_output;

        ut.expect(l_output).to_be_null();
    END tree_unknown_root_is_silent;

    PROCEDURE tree_ignores_status IS
        l_output VARCHAR2(32767);
        l_status customers.status%TYPE;
    BEGIN
        SELECT status
        INTO l_status
        FROM customers
        WHERE customer_id = ut_estate_fixture.c_dept_n1a;

        pkg_customer_hier.print_tree(ut_estate_fixture.c_branch_n1);
        l_output := ut_estate_fixture.captured_output;

        -- DEPT-N1A is on hold, and the walk still passes through it to reach
        -- TEAM-N1A1. Nothing in the procedure filters on status.
        ut.expect(l_status).to_equal('H');
        ut.expect(l_output).to_be_like('%DEPT-N1A level=2%');
        ut.expect(l_output).to_be_like('%TEAM-N1A1 level=3%');
    END tree_ignores_status;

    ---------------------------------------------------------------------------
    -- list_ancestors
    ---------------------------------------------------------------------------

    PROCEDURE ancestors_self_then_parents IS
        l_actual   SYS_REFCURSOR;
        l_expected SYS_REFCURSOR;
    BEGIN
        pkg_customer_hier.list_ancestors(
            p_customer_id => ut_estate_fixture.c_team_n1a1,
            p_result      => l_actual
        );

        -- CONNECT BY PRIOR parent_customer_id = customer_id walks upwards, so
        -- LEVEL 1 is the customer itself and the root has the highest depth.
        OPEN l_expected FOR
            SELECT ut_estate_fixture.c_team_n1a1 AS customer_id, 1 AS depth
            FROM DUAL
            UNION ALL SELECT ut_estate_fixture.c_dept_n1a, 2 FROM DUAL
            UNION ALL SELECT ut_estate_fixture.c_branch_n1, 3 FROM DUAL
            UNION ALL SELECT ut_estate_fixture.c_region_north, 4 FROM DUAL
            UNION ALL SELECT ut_estate_fixture.c_root_customer, 5 FROM DUAL;

        ut.expect(l_actual).to_equal(l_expected).include('CUSTOMER_ID,DEPTH');
    END ancestors_self_then_parents;

    PROCEDURE ancestors_of_root_is_self IS
        l_actual   SYS_REFCURSOR;
        l_expected SYS_REFCURSOR;
    BEGIN
        pkg_customer_hier.list_ancestors(
            p_customer_id => ut_estate_fixture.c_root_customer,
            p_result      => l_actual
        );

        OPEN l_expected FOR
            SELECT ut_estate_fixture.c_root_customer AS customer_id, 1 AS depth
            FROM DUAL;

        ut.expect(l_actual).to_equal(l_expected).include('CUSTOMER_ID,DEPTH');
    END ancestors_of_root_is_self;

    PROCEDURE ancestors_unknown_is_empty IS
        l_actual SYS_REFCURSOR;
    BEGIN
        pkg_customer_hier.list_ancestors(
            p_customer_id => ut_estate_fixture.c_missing_customer,
            p_result      => l_actual
        );

        ut.expect(l_actual).to_be_empty();
    END ancestors_unknown_is_empty;

    ---------------------------------------------------------------------------
    -- find_unordered_customers
    ---------------------------------------------------------------------------

    PROCEDURE unordered_lists_quiet_actives IS
        l_ids t_id_flags;
    BEGIN
        l_ids := unordered_ids;

        -- Nine of the twelve fixture customers qualify: ten are active, and
        -- SOLO-RECENT is removed by its order from ten days ago.
        ut.expect(l_ids.COUNT).to_equal(9);
        ut.expect(l_ids.EXISTS(ut_estate_fixture.c_root_customer)).to_be_true();
        ut.expect(l_ids.EXISTS(ut_estate_fixture.c_region_north)).to_be_true();
        ut.expect(l_ids.EXISTS(ut_estate_fixture.c_region_south)).to_be_true();
        ut.expect(l_ids.EXISTS(ut_estate_fixture.c_branch_n1)).to_be_true();
        ut.expect(l_ids.EXISTS(ut_estate_fixture.c_branch_n2)).to_be_true();
        ut.expect(l_ids.EXISTS(ut_estate_fixture.c_team_n1a1)).to_be_true();
        -- SOLO-STALE ordered 100 days ago, which is outside the window.
        ut.expect(l_ids.EXISTS(ut_estate_fixture.c_solo_stale)).to_be_true();
        ut.expect(l_ids.EXISTS(ut_estate_fixture.c_empty_channel)).to_be_true();
        ut.expect(l_ids.EXISTS(ut_estate_fixture.c_mixed_case_code)).to_be_true();
        ut.expect(l_ids.EXISTS(ut_estate_fixture.c_solo_recent)).to_be_false();
    END unordered_lists_quiet_actives;

    PROCEDURE unordered_drops_new_orderer IS
        l_before t_id_flags;
        l_after  t_id_flags;
    BEGIN
        l_before := unordered_ids;

        INSERT INTO orders (
            order_number, customer_id, order_status, ordered_at, requested_by
        )
        VALUES (
            'UT-CH-01', ut_estate_fixture.c_root_customer, 'OPEN',
            SYSDATE - 1, 'BATCH'
        );

        l_after := unordered_ids;

        ut.expect(l_before.EXISTS(ut_estate_fixture.c_root_customer)).to_be_true();
        ut.expect(l_after.EXISTS(ut_estate_fixture.c_root_customer)).to_be_false();
        ut.expect(l_after.COUNT).to_equal(l_before.COUNT - 1);
    END unordered_drops_new_orderer;

    PROCEDURE unordered_ignores_non_active IS
        l_ids t_id_flags;
    BEGIN
        l_ids := unordered_ids;

        -- DEPT-N1A is on hold and SOLO-INACTIVE is inactive, and neither has an
        -- order at all. The status filter, not the order history, excludes them.
        ut.expect(l_ids.EXISTS(ut_estate_fixture.c_dept_n1a)).to_be_false();
        ut.expect(l_ids.EXISTS(ut_estate_fixture.c_solo_inactive)).to_be_false();
    END unordered_ignores_non_active;

    ---------------------------------------------------------------------------
    -- empty string and trigger behaviour
    ---------------------------------------------------------------------------

    PROCEDURE empty_channel_is_null IS
        l_channel   customers.preferred_channel%TYPE;
        l_is_null   PLS_INTEGER;
        l_new_id    customers.customer_id%TYPE;
    BEGIN
        SELECT preferred_channel,
               CASE WHEN preferred_channel IS NULL THEN 1 ELSE 0 END
        INTO l_channel, l_is_null
        FROM customers
        WHERE customer_id = ut_estate_fixture.c_empty_channel;

        -- Loaded from fixtures/010_customers.sql with preferred_channel = ''.
        -- Oracle stored NULL, and ck_customers_channel (preferred_channel <> '')
        -- evaluated to UNKNOWN rather than FALSE, so the row was accepted.
        ut.expect(l_is_null).to_equal(1);
        ut.expect(l_channel).to_be_null();

        -- Same behaviour on a fresh insert, so the constraint never rejects an
        -- empty string on Oracle.
        INSERT INTO customers (customer_code, display_name, preferred_channel)
        VALUES ('UT-EMPTY-CH', 'Empty Channel Insert Fixture', '')
        RETURNING customer_id INTO l_new_id;

        SELECT CASE WHEN preferred_channel IS NULL THEN 1 ELSE 0 END
        INTO l_is_null
        FROM customers
        WHERE customer_id = l_new_id;

        ut.expect(l_is_null).to_equal(1);
    END empty_channel_is_null;

    PROCEDURE trigger_normalizes_code IS
        l_code     customers.customer_code%TYPE;
        l_status   customers.status%TYPE;
        l_new_id   customers.customer_id%TYPE;
        l_new_code customers.customer_code%TYPE;
    BEGIN
        SELECT customer_code
        INTO l_code
        FROM customers
        WHERE customer_id = ut_estate_fixture.c_mixed_case_code;

        -- The fixture inserted '  mixed-case  '.
        ut.expect(l_code).to_equal('MIXED-CASE');

        INSERT INTO customers (customer_code, display_name, status)
        VALUES ('  ut-trigger-c  ', 'Trigger Fixture', NULL)
        RETURNING customer_id, customer_code, status
        INTO l_new_id, l_new_code, l_status;

        ut.expect(l_new_id).to_be_not_null();
        ut.expect(l_new_code).to_equal('UT-TRIGGER-C');
        ut.expect(l_status).to_equal('A');
    END trigger_normalizes_code;

END ut_pkg_customer_hier;
/
