-- Converted from oracle-legacy-estate/packages/pkg_order_mgmt.pks / .pkb
--
-- Package becomes schema pkg_order_mgmt. Procedures become functions.
-- OUT parameters become return values, and SYS_REFCURSOR result sets become
-- SETOF returns, which is what psycopg wants anyway (see the converted DAO in
-- oracle-legacy-estate/app/dao_postgres.py).
--
-- Package state
-- -------------
-- Oracle package variables g_call_count and g_last_order_id live for the
-- duration of the session. The nearest PostgreSQL equivalent without an
-- extension is a session GUC in a custom namespace, which is what these
-- accessors wrap. One real difference: GUC assignments are transactional, so a
-- rollback undoes them, while Oracle package state survives a rollback. Called
-- out in CONVERSION-NOTES.md as needing a human decision if any caller relies
-- on the counter after a failure.

CREATE OR REPLACE FUNCTION pkg_order_mgmt.g_call_count()
RETURNS bigint
LANGUAGE sql
AS $$
    SELECT COALESCE(NULLIF(current_setting('pkg_order_mgmt.call_count', true), ''), '0')::bigint;
$$;

CREATE OR REPLACE FUNCTION pkg_order_mgmt.g_last_order_id()
RETURNS bigint
LANGUAGE sql
AS $$
    SELECT NULLIF(current_setting('pkg_order_mgmt.last_order_id', true), '')::bigint;
$$;

CREATE OR REPLACE FUNCTION pkg_order_mgmt.reset_package_state()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM set_config('pkg_order_mgmt.call_count', '0', false);
    PERFORM set_config('pkg_order_mgmt.last_order_id', '', false);
END;
$$;

-- create_order ---------------------------------------------------------------
--
-- Oracle constructs handled here: SAVEPOINT plus ROLLBACK TO inside the
-- exception handler, DECODE, NVL2, SELECT ... FROM DUAL, SYSDATE, dynamic SQL
-- built by concatenating an identifier, RETURNING INTO, DUP_VAL_ON_INDEX,
-- RAISE_APPLICATION_ERROR and DBMS_OUTPUT.
--
-- SAVEPOINT before_order / ROLLBACK TO before_order becomes the BEGIN ...
-- EXCEPTION block below. PL/pgSQL opens an internal subtransaction for any
-- block with an exception handler and rolls it back before running the handler,
-- so the savepoint is implicit. Explicit SAVEPOINT statements are not allowed
-- inside a PostgreSQL function at all.
CREATE OR REPLACE FUNCTION pkg_order_mgmt.create_order(
    p_order_number  varchar,
    p_customer_id   bigint,
    p_requested_by  varchar
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    l_default_status varchar(16);
    l_table_name     text := 'orders';
    l_schema_name    text := 'retail';
    l_lookup_sql     text;
    l_order_id       bigint;
    l_last_order_id  bigint;
BEGIN
    PERFORM set_config('pkg_order_mgmt.call_count',
                       (pkg_order_mgmt.g_call_count() + 1)::text,
                       false);

    -- DECODE(NVL(p_requested_by,'BATCH'),'BATCH','OPEN','HELD'), no DUAL needed
    l_default_status := CASE COALESCE(p_requested_by, 'BATCH')
                            WHEN 'BATCH' THEN 'OPEN'
                            ELSE 'HELD'
                        END;

    INSERT INTO retail.orders (
        order_number,
        customer_id,
        requested_by,
        order_status,
        ordered_at
    )
    VALUES (
        p_order_number,
        p_customer_id,
        COALESCE(p_requested_by, 'BATCH'),   -- NVL2(x, x, 'BATCH')
        l_default_status,
        retail.sysdate()
    )
    RETURNING order_id INTO l_order_id;

    -- Oracle concatenated the table name straight into the statement text.
    -- format() with %I quotes the identifier and %L would quote literals, which
    -- removes the injection path the original had.
    l_lookup_sql := format('SELECT order_id FROM %I.%I WHERE order_number = $1',
                           l_schema_name, l_table_name);
    EXECUTE l_lookup_sql INTO l_last_order_id USING p_order_number;

    PERFORM set_config('pkg_order_mgmt.last_order_id', l_last_order_id::text, false);

    -- DBMS_OUTPUT.PUT_LINE
    RAISE NOTICE 'created order % call=%', l_last_order_id, pkg_order_mgmt.g_call_count();

    RETURN l_order_id;
EXCEPTION
    WHEN unique_violation THEN            -- DUP_VAL_ON_INDEX
        RAISE EXCEPTION 'Order number already exists' USING ERRCODE = 'OR901';
END;
$$;

-- add_order_line -------------------------------------------------------------
CREATE OR REPLACE FUNCTION pkg_order_mgmt.add_order_line(
    p_order_id   bigint,
    p_product_id bigint,
    p_quantity   numeric,
    p_unit_price numeric
)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
    l_next_line numeric;
BEGIN
    SELECT COALESCE(MAX(line_number), 0) + 1
    INTO l_next_line
    FROM retail.order_lines
    WHERE order_id = p_order_id;

    INSERT INTO retail.order_lines (
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
        COALESCE(p_quantity, 1),
        p_unit_price,
        0,
        COALESCE(p_quantity, 1) * p_unit_price
    );

    PERFORM pkg_order_mgmt.refresh_order_total(p_order_id);

    -- Returned so callers and tests can see the assigned line number. The
    -- Oracle procedure had no OUT parameter.
    RETURN l_next_line;
END;
$$;

-- refresh_order_total --------------------------------------------------------
CREATE OR REPLACE FUNCTION pkg_order_mgmt.refresh_order_total(p_order_id bigint)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    l_subtotal numeric(14, 2);
    l_discount numeric(14, 2);
    l_tax      numeric(14, 2);
BEGIN
    SELECT COALESCE(SUM(extended_amount), 0),
           COALESCE(SUM(extended_amount * discount_rate / 100), 0)
    INTO l_subtotal, l_discount
    FROM retail.order_lines
    WHERE order_id = p_order_id;

    l_tax := round((l_subtotal - l_discount) * 0.0825, 2);

    UPDATE retail.orders
    SET subtotal_amount = l_subtotal,
        discount_amount = l_discount,
        tax_amount = l_tax,
        total_amount = l_subtotal - l_discount + l_tax
    WHERE order_id = p_order_id;
END;
$$;

-- list_customer_orders -------------------------------------------------------
--
-- The Oracle version paginated with two nested inline views and ROWNUM, and
-- carried the hints /*+ FIRST_ROWS(25) INDEX(o ix_orders_customer_date) */.
-- PostgreSQL has no hint syntax in core, so the hints are dropped and the
-- index they named still exists (ix_orders_customer_date, V004). LIMIT and
-- OFFSET express the same window. Ties on ordered_at are broken by order_id so
-- page boundaries are stable, which the ROWNUM version did not promise.
CREATE OR REPLACE FUNCTION pkg_order_mgmt.list_customer_orders(
    p_customer_id bigint,
    p_page_number integer DEFAULT 1,
    p_page_size   integer DEFAULT 25
)
RETURNS TABLE (
    order_id     bigint,
    order_number varchar,
    order_status varchar,
    ordered_at   timestamp(0),
    total_amount numeric
)
LANGUAGE plpgsql
AS $$
DECLARE
    l_page_number integer := COALESCE(p_page_number, 1);
    l_page_size   integer := COALESCE(p_page_size, 25);
BEGIN
    RETURN QUERY
    SELECT o.order_id,
           o.order_number,
           o.order_status,
           o.ordered_at,
           o.total_amount
    FROM retail.orders o
    WHERE o.customer_id = p_customer_id
    ORDER BY o.ordered_at DESC, o.order_id DESC
    LIMIT l_page_size
    OFFSET (l_page_number - 1) * l_page_size;
END;
$$;

-- load_order_totals ----------------------------------------------------------
--
-- Oracle used a global temporary table, BULK COLLECT into two collections and
-- FORALL to insert. PostgreSQL has no collection bulk binding and does not need
-- one: the whole thing is a single set-based INSERT ... SELECT, which is faster
-- than the row-at-a-time original and removes the two arrays. The GTT becomes
-- the session temp table created by retail.ensure_gtt_order_totals().
--
-- ON COMMIT DELETE ROWS means the caller must read the rows in the same
-- transaction that filled them, exactly as in Oracle.
CREATE OR REPLACE FUNCTION pkg_order_mgmt.load_order_totals(p_customer_id bigint)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    l_loaded integer;
BEGIN
    PERFORM retail.ensure_gtt_order_totals();
    DELETE FROM gtt_order_totals;

    INSERT INTO gtt_order_totals (order_id, line_count, calculated_total)
    SELECT o.order_id,
           (SELECT COUNT(*) FROM retail.order_lines ol WHERE ol.order_id = o.order_id),
           COALESCE(o.total_amount, 0)
    FROM retail.orders o
    WHERE o.customer_id = p_customer_id
    ORDER BY o.order_id;

    GET DIAGNOSTICS l_loaded = ROW_COUNT;
    RAISE NOTICE 'loaded totals=%', l_loaded;
    RETURN l_loaded;
EXCEPTION
    WHEN OTHERS THEN
        -- ROLLBACK TO before_totals is the implicit subtransaction rollback.
        RAISE EXCEPTION 'Could not load order totals: %', SQLERRM USING ERRCODE = 'OR902';
END;
$$;

-- summarize_order ------------------------------------------------------------
--
-- Oracle constructs handled here: cursor FOR loop, REVERSE FOR loop, GREATEST,
-- an (+) outer join that had to return a row even with no invoice, and three
-- DBMS_OUTPUT calls. The DBMS_OUTPUT text is emitted as RAISE NOTICE and also
-- returned, because notices are not a testable interface.
CREATE OR REPLACE FUNCTION pkg_order_mgmt.summarize_order(p_order_id bigint)
RETURNS TABLE (
    line_count      integer,
    marker          text,
    unpriced_lines  integer,
    invoice_label   text
)
LANGUAGE plpgsql
AS $$
DECLARE
    l_line_count     integer := 0;
    l_unpriced       integer := 0;
    l_code           text;
    line_rec         record;
    invoice_rec      record;
    l_invoice_label  text := NULL;
BEGIN
    FOR line_rec IN
        SELECT ol.line_number, ol.product_id, ol.quantity, ol.extended_amount
        FROM retail.order_lines ol
        WHERE ol.order_id = p_order_id
        ORDER BY ol.line_number
    LOOP
        l_line_count := l_line_count + 1;
        IF line_rec.extended_amount IS NULL THEN
            l_unpriced := l_unpriced + 1;
            RAISE NOTICE 'line has no amount: %', line_rec.line_number;
        END IF;
    END LOOP;

    -- FOR i IN REVERSE 1..GREATEST(l_line_count, 1) LOOP
    -- PL/pgSQL spells the descending loop "REVERSE high..low", the opposite
    -- argument order from PL/SQL. Same iteration set, same final value.
    FOR i IN REVERSE GREATEST(l_line_count, 1)..1 LOOP
        l_code := 'LINE-' || i::text;
    END LOOP;

    FOR invoice_rec IN
        SELECT o.order_id, i.invoice_id, i.invoice_status
        FROM retail.orders o
        LEFT JOIN retail.invoices i ON o.order_id = i.order_id
        WHERE o.order_id = p_order_id
    LOOP
        l_invoice_label := format('order=%s invoice=%s',
                                  invoice_rec.order_id,
                                  COALESCE(invoice_rec.invoice_id::text, 'NONE'));
        RAISE NOTICE '%', l_invoice_label;
    END LOOP;

    RAISE NOTICE 'lines=% marker=%', l_line_count, l_code;

    RETURN QUERY SELECT l_line_count, l_code, l_unpriced, l_invoice_label;
END;
$$;
