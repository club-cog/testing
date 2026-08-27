-- Converted from oracle-legacy-estate/packages/pkg_customer_hier.pks / .pkb
--
-- Package becomes schema pkg_customer_hier. Every CONNECT BY becomes a
-- recursive CTE. LEVEL becomes a depth column carried by the recursion, and
-- ORDER SIBLINGS BY becomes an ordering path array.

-- print_tree -----------------------------------------------------------------
--
-- Oracle: START WITH ... CONNECT BY PRIOR customer_id = parent_customer_id,
-- LEVEL, LPAD indentation, ORDER SIBLINGS BY customer_code, DBMS_OUTPUT.
--
-- ORDER SIBLINGS BY has no direct equivalent. The recursion accumulates an
-- array of customer_code values (sort_path) and the final ORDER BY sorts on it,
-- which reproduces depth-first traversal with siblings in code order.
CREATE OR REPLACE FUNCTION pkg_customer_hier.print_tree(p_root_customer_id bigint)
RETURNS TABLE (
    customer_id        bigint,
    customer_code      varchar,
    parent_customer_id bigint,
    hierarchy_level    integer,
    display_path       text
)
LANGUAGE plpgsql
AS $$
DECLARE
    rec record;
BEGIN
    FOR rec IN
        WITH RECURSIVE tree AS (
            SELECT c.customer_id,
                   c.customer_code,
                   c.parent_customer_id,
                   1 AS hierarchy_level,
                   ARRAY[c.customer_code]::text[] AS sort_path
            FROM retail.customers c
            WHERE c.customer_id = p_root_customer_id
            UNION ALL
            SELECT c.customer_id,
                   c.customer_code,
                   c.parent_customer_id,
                   t.hierarchy_level + 1,
                   t.sort_path || c.customer_code::text
            FROM retail.customers c
            JOIN tree t ON c.parent_customer_id = t.customer_id
        )
        SELECT t.customer_id,
               t.customer_code,
               t.parent_customer_id,
               t.hierarchy_level,
               repeat(' ', (t.hierarchy_level - 1) * 2) || t.customer_code AS display_path
        FROM tree t
        ORDER BY t.sort_path
    LOOP
        -- DBMS_OUTPUT.PUT_LINE
        RAISE NOTICE '% level=%', rec.display_path, rec.hierarchy_level;
        customer_id        := rec.customer_id;
        customer_code      := rec.customer_code;
        parent_customer_id := rec.parent_customer_id;
        hierarchy_level    := rec.hierarchy_level;
        display_path       := rec.display_path;
        RETURN NEXT;
    END LOOP;
END;
$$;

-- list_ancestors -------------------------------------------------------------
--
-- Oracle walked upward with CONNECT BY PRIOR parent_customer_id = customer_id
-- and returned a SYS_REFCURSOR. The refcursor becomes a SETOF return.
-- The root row is depth 1, matching Oracle LEVEL.
CREATE OR REPLACE FUNCTION pkg_customer_hier.list_ancestors(p_customer_id bigint)
RETURNS TABLE (
    customer_id        bigint,
    customer_code      varchar,
    parent_customer_id bigint,
    depth              integer
)
LANGUAGE sql
AS $$
    WITH RECURSIVE up AS (
        SELECT c.customer_id, c.customer_code, c.parent_customer_id, 1 AS depth
        FROM retail.customers c
        WHERE c.customer_id = p_customer_id
        UNION ALL
        SELECT c.customer_id, c.customer_code, c.parent_customer_id, u.depth + 1
        FROM retail.customers c
        JOIN up u ON u.parent_customer_id = c.customer_id
    )
    SELECT up.customer_id, up.customer_code, up.parent_customer_id, up.depth
    FROM up
    ORDER BY up.depth;
$$;

-- find_unordered_customers ---------------------------------------------------
--
-- MINUS becomes EXCEPT. Both remove duplicates, so the result set matches.
-- Oracle ordered nothing here and neither does EXCEPT, so an explicit ORDER BY
-- is added for a stable read.
--
-- SYSDATE - 90 becomes retail.sysdate() - interval '90 days'. Oracle date
-- arithmetic counts days for a bare number; the interval says so out loud.
CREATE OR REPLACE FUNCTION pkg_customer_hier.find_unordered_customers()
RETURNS TABLE (
    customer_id   bigint,
    customer_code varchar
)
LANGUAGE sql
AS $$
    SELECT * FROM (
        SELECT c.customer_id, c.customer_code
        FROM retail.customers c
        WHERE c.status = 'A'
        EXCEPT
        SELECT c.customer_id, c.customer_code
        FROM retail.customers c
        JOIN retail.orders o ON c.customer_id = o.customer_id
        WHERE o.ordered_at >= retail.sysdate() - interval '90 days'
    ) q
    ORDER BY q.customer_id;
$$;

-- descendant_count -----------------------------------------------------------
--
-- Oracle counted rows whose customer_id was IN the CONNECT BY set, which
-- includes the root itself, so the name overstates what it returns. Behaviour
-- is preserved, including the root row. NVL(l_count, 0) is redundant because
-- COUNT never returns NULL; dropped.
CREATE OR REPLACE FUNCTION pkg_customer_hier.descendant_count(p_root_customer_id bigint)
RETURNS bigint
LANGUAGE sql
AS $$
    WITH RECURSIVE tree AS (
        SELECT c.customer_id
        FROM retail.customers c
        WHERE c.customer_id = p_root_customer_id
        UNION ALL
        SELECT c.customer_id
        FROM retail.customers c
        JOIN tree t ON c.parent_customer_id = t.customer_id
    )
    SELECT COUNT(*) FROM tree;
$$;
