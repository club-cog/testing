CREATE OR REPLACE PACKAGE BODY pkg_order_mgmt AS

    g_call_count    PLS_INTEGER := 0;

    PROCEDURE create_order (
        p_order_number    IN orders.order_number%TYPE,
        p_customer_id     IN orders.customer_id%TYPE,
        p_requested_by    IN orders.requested_by%TYPE,
        p_order_id        OUT orders.order_id%TYPE
    ) IS
        l_default_status  orders.order_status%TYPE;
        l_table_name      VARCHAR2(30) := 'ORDERS';
        l_lookup_sql      VARCHAR2(4000);
    BEGIN
        SAVEPOINT before_order;
        g_call_count := NVL(g_call_count, 0) + 1;

        SELECT DECODE(NVL(p_requested_by, 'BATCH'), 'BATCH', 'OPEN', 'HELD')
        INTO l_default_status
        FROM DUAL;

        INSERT INTO orders (
            order_number,
            customer_id,
            requested_by,
            order_status,
            ordered_at
        )
        VALUES (
            p_order_number,
            p_customer_id,
            NVL2(p_requested_by, p_requested_by, 'BATCH'),
            l_default_status,
            SYSDATE
        )
        RETURNING order_id INTO p_order_id;

        l_lookup_sql := 'SELECT order_id FROM ' || l_table_name
                     || ' WHERE order_number = :order_number';
        EXECUTE IMMEDIATE l_lookup_sql INTO g_last_order_id USING p_order_number;

        DBMS_OUTPUT.PUT_LINE(
            'created order ' || g_last_order_id || ' call=' || g_call_count
        );
    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            ROLLBACK TO before_order;
            RAISE_APPLICATION_ERROR(-20901, 'Order number already exists');
        WHEN OTHERS THEN
            ROLLBACK TO before_order;
            RAISE;
    END create_order;

    PROCEDURE add_order_line (
        p_order_id        IN order_lines.order_id%TYPE,
        p_product_id      IN order_lines.product_id%TYPE,
        p_quantity        IN order_lines.quantity%TYPE,
        p_unit_price      IN order_lines.unit_price%TYPE
    ) IS
        l_next_line       order_lines.line_number%TYPE;
    BEGIN
        SELECT NVL(MAX(line_number), 0) + 1
        INTO l_next_line
        FROM order_lines
        WHERE order_id = p_order_id;

        INSERT INTO order_lines (
            order_id,
            line_number,
            product_id,
            quantity,
            unit_price,
            discount_rate,
            extended_amount
        )
        VALUES (
            p_order_id,
            l_next_line,
            p_product_id,
            NVL(p_quantity, 1),
            p_unit_price,
            0,
            NVL(p_quantity, 1) * p_unit_price
        );

        refresh_order_total(p_order_id);
    END add_order_line;

    PROCEDURE refresh_order_total (
        p_order_id IN orders.order_id%TYPE
    ) IS
        l_subtotal       orders.subtotal_amount%TYPE;
        l_discount       orders.discount_amount%TYPE;
        l_tax            orders.tax_amount%TYPE;
    BEGIN
        SELECT NVL(SUM(extended_amount), 0),
               NVL(SUM(extended_amount * discount_rate / 100), 0)
        INTO l_subtotal, l_discount
        FROM order_lines
        WHERE order_id = p_order_id;

        l_tax := ROUND((l_subtotal - l_discount) * 0.0825, 2);

        UPDATE orders
        SET subtotal_amount = l_subtotal,
            discount_amount = l_discount,
            tax_amount = l_tax,
            total_amount = l_subtotal - l_discount + l_tax
        WHERE order_id = p_order_id;
    END refresh_order_total;

    PROCEDURE list_customer_orders (
        p_customer_id IN orders.customer_id%TYPE,
        p_page_number IN PLS_INTEGER,
        p_page_size   IN PLS_INTEGER,
        p_result      OUT SYS_REFCURSOR
    ) IS
        l_start_row PLS_INTEGER := ((NVL(p_page_number, 1) - 1)
                                    * NVL(p_page_size, 25)) + 1;
        l_end_row   PLS_INTEGER := NVL(p_page_number, 1)
                                  * NVL(p_page_size, 25);
    BEGIN
        OPEN p_result FOR
            SELECT order_id, order_number, order_status, ordered_at, total_amount
            FROM (
                SELECT /*+ FIRST_ROWS(25) INDEX(o ix_orders_customer_date) */
                       o.order_id,
                       o.order_number,
                       o.order_status,
                       o.ordered_at,
                       o.total_amount,
                       ROWNUM AS rn
                FROM (
                    SELECT order_id, order_number, order_status,
                           ordered_at, total_amount
                    FROM orders o
                    WHERE o.customer_id = p_customer_id
                    ORDER BY o.ordered_at DESC
                ) o
                WHERE ROWNUM <= l_end_row
            )
            WHERE rn >= l_start_row
            ORDER BY rn;
    END list_customer_orders;

    PROCEDURE load_order_totals (
        p_customer_id IN orders.customer_id%TYPE
    ) IS
        TYPE t_id_list IS TABLE OF orders.order_id%TYPE;
        TYPE t_total_list IS TABLE OF orders.total_amount%TYPE;
        l_ids       t_id_list;
        l_totals    t_total_list;
    BEGIN
        SAVEPOINT before_totals;
        DELETE FROM gtt_order_totals;

        SELECT o.order_id, NVL(o.total_amount, 0)
        BULK COLLECT INTO l_ids, l_totals
        FROM orders o
        WHERE o.customer_id = p_customer_id
        ORDER BY o.order_id;

        FORALL i IN 1..l_ids.COUNT
            INSERT INTO gtt_order_totals (order_id, line_count, calculated_total)
            SELECT l_ids(i), COUNT(*), l_totals(i)
            FROM order_lines
            WHERE order_id = l_ids(i);

        DBMS_OUTPUT.PUT_LINE('loaded totals=' || l_ids.COUNT);
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO before_totals;
            RAISE_APPLICATION_ERROR(-20902, 'Could not load order totals: ' || SQLERRM);
    END load_order_totals;

    PROCEDURE summarize_order (
        p_order_id IN orders.order_id%TYPE
    ) IS
        l_line_count PLS_INTEGER := 0;
        l_code       VARCHAR2(80);
    BEGIN
        FOR line_rec IN (
            SELECT line_number, product_id, quantity, extended_amount
            FROM order_lines
            WHERE order_id = p_order_id
            ORDER BY line_number
        ) LOOP
            l_line_count := l_line_count + 1;
            IF line_rec.extended_amount IS NULL THEN
                DBMS_OUTPUT.PUT_LINE('line has no amount: ' || line_rec.line_number);
            END IF;
        END LOOP;

        FOR i IN REVERSE 1..GREATEST(l_line_count, 1) LOOP
            l_code := 'LINE-' || TO_CHAR(i);
        END LOOP;

        -- Old screen expects rows even when an invoice has not been created.
        FOR invoice_rec IN (
            SELECT o.order_id, i.invoice_id, i.invoice_status
            FROM orders o, invoices i
            WHERE o.order_id = p_order_id
              AND o.order_id = i.order_id(+)
        ) LOOP
            DBMS_OUTPUT.PUT_LINE(
                'order=' || invoice_rec.order_id
                || ' invoice=' || NVL(TO_CHAR(invoice_rec.invoice_id), 'NONE')
            );
        END LOOP;

        DBMS_OUTPUT.PUT_LINE('lines=' || l_line_count || ' marker=' || l_code);
    END summarize_order;

END pkg_order_mgmt;
/
