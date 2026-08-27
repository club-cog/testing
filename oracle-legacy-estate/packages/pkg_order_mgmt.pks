CREATE OR REPLACE PACKAGE pkg_order_mgmt AS
    g_last_order_id orders.order_id%TYPE;

    PROCEDURE create_order (
        p_order_number    IN orders.order_number%TYPE,
        p_customer_id     IN orders.customer_id%TYPE,
        p_requested_by    IN orders.requested_by%TYPE,
        p_order_id        OUT orders.order_id%TYPE
    );

    PROCEDURE add_order_line (
        p_order_id        IN order_lines.order_id%TYPE,
        p_product_id      IN order_lines.product_id%TYPE,
        p_quantity        IN order_lines.quantity%TYPE,
        p_unit_price      IN order_lines.unit_price%TYPE
    );

    PROCEDURE refresh_order_total (
        p_order_id        IN orders.order_id%TYPE
    );

    PROCEDURE list_customer_orders (
        p_customer_id     IN orders.customer_id%TYPE,
        p_page_number     IN PLS_INTEGER,
        p_page_size       IN PLS_INTEGER,
        p_result           OUT SYS_REFCURSOR
    );

    PROCEDURE load_order_totals (
        p_customer_id     IN orders.customer_id%TYPE
    );

    PROCEDURE summarize_order (
        p_order_id        IN orders.order_id%TYPE
    );
END pkg_order_mgmt;
/
