CREATE OR REPLACE PACKAGE BODY pkg_customer_hier AS

    PROCEDURE print_tree (
        p_root_customer_id IN customers.customer_id%TYPE
    ) IS
    BEGIN
        FOR customer_rec IN (
            SELECT customer_id,
                   customer_code,
                   parent_customer_id,
                   LEVEL AS hierarchy_level,
                   LPAD(' ', (LEVEL - 1) * 2) || customer_code AS display_path
            FROM customers
            START WITH customer_id = p_root_customer_id
            CONNECT BY PRIOR customer_id = parent_customer_id
            ORDER SIBLINGS BY customer_code
        ) LOOP
            DBMS_OUTPUT.PUT_LINE(
                customer_rec.display_path
                || ' level=' || customer_rec.hierarchy_level
            );
        END LOOP;
    END print_tree;

    PROCEDURE list_ancestors (
        p_customer_id IN customers.customer_id%TYPE,
        p_result      OUT SYS_REFCURSOR
    ) IS
    BEGIN
        OPEN p_result FOR
            SELECT customer_id, customer_code, parent_customer_id, LEVEL AS depth
            FROM customers
            START WITH customer_id = p_customer_id
            CONNECT BY PRIOR parent_customer_id = customer_id
            ORDER BY depth;
    END list_ancestors;

    PROCEDURE find_unordered_customers (
        p_result OUT SYS_REFCURSOR
    ) IS
    BEGIN
        OPEN p_result FOR
            SELECT customer_id, customer_code
            FROM customers
            WHERE status = 'A'
            MINUS
            SELECT c.customer_id, c.customer_code
            FROM customers c, orders o
            WHERE c.customer_id = o.customer_id
              AND o.ordered_at >= SYSDATE - 90;
    END find_unordered_customers;

    FUNCTION descendant_count (
        p_root_customer_id IN customers.customer_id%TYPE
    ) RETURN NUMBER IS
        l_count NUMBER;
    BEGIN
        SELECT COUNT(*)
        INTO l_count
        FROM customers
        WHERE customer_id IN (
            SELECT customer_id
            FROM customers
            START WITH customer_id = p_root_customer_id
            CONNECT BY PRIOR customer_id = parent_customer_id
        );

        RETURN NVL(l_count, 0);
    END descendant_count;

END pkg_customer_hier;
/
