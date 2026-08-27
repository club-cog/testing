CREATE OR REPLACE PACKAGE pkg_customer_hier AS
    PROCEDURE print_tree (
        p_root_customer_id IN customers.customer_id%TYPE
    );

    PROCEDURE list_ancestors (
        p_customer_id IN customers.customer_id%TYPE,
        p_result       OUT SYS_REFCURSOR
    );

    PROCEDURE find_unordered_customers (
        p_result OUT SYS_REFCURSOR
    );

    FUNCTION descendant_count (
        p_root_customer_id IN customers.customer_id%TYPE
    ) RETURN NUMBER;
END pkg_customer_hier;
/
