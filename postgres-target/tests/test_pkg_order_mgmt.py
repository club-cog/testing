"""Behaviour of the converted PKG_ORDER_MGMT functions."""

from __future__ import annotations

import psycopg
import pytest
from conftest import dec, one, rows, scalar


def test_create_order_defaults_status_open_for_batch(cur):
    order_id = scalar(
        cur,
        "SELECT pkg_order_mgmt.create_order('ORD-T001', 1001, NULL)",
    )
    status, requested_by = one(
        cur,
        "SELECT order_status, requested_by FROM retail.orders WHERE order_id = %s",
        (order_id,),
    )
    # DECODE(NVL(p_requested_by,'BATCH'),'BATCH','OPEN','HELD') plus NVL2
    assert status == "OPEN"
    assert requested_by == "BATCH"


def test_create_order_holds_when_requested_by_present(cur):
    order_id = scalar(
        cur, "SELECT pkg_order_mgmt.create_order('ORD-T002', 1001, 'analyst')"
    )
    assert scalar(
        cur, "SELECT order_status FROM retail.orders WHERE order_id = %s", (order_id,)
    ) == "HELD"


def test_create_order_normalises_number_through_trigger(cur):
    order_id = scalar(
        cur, "SELECT pkg_order_mgmt.create_order('  ord-t003  ', 1001, NULL)"
    )
    assert scalar(
        cur, "SELECT order_number FROM retail.orders WHERE order_id = %s", (order_id,)
    ) == "ORD-T003"


def test_package_state_counter_and_last_order_id(cur):
    """Oracle package variables g_call_count and g_last_order_id, held in
    session GUCs. g_last_order_id is set through the dynamic SQL lookup."""
    cur.execute("SELECT pkg_order_mgmt.reset_package_state()")
    assert scalar(cur, "SELECT pkg_order_mgmt.g_call_count()") == 0

    first = scalar(cur, "SELECT pkg_order_mgmt.create_order('ORD-T004', 1001, NULL)")
    assert scalar(cur, "SELECT pkg_order_mgmt.g_call_count()") == 1
    assert scalar(cur, "SELECT pkg_order_mgmt.g_last_order_id()") == first

    second = scalar(cur, "SELECT pkg_order_mgmt.create_order('ORD-T005', 1001, NULL)")
    assert scalar(cur, "SELECT pkg_order_mgmt.g_call_count()") == 2
    assert scalar(cur, "SELECT pkg_order_mgmt.g_last_order_id()") == second


def test_package_state_is_transactional_unlike_oracle(conn, cur):
    """Deliberate difference, documented in CONVERSION-NOTES.md.

    Oracle package state survives a rollback. A session GUC does not, so the
    counter goes back to whatever it was when the transaction began.
    """
    cur.execute("SELECT pkg_order_mgmt.reset_package_state()")
    conn.commit()

    cur.execute("SELECT pkg_order_mgmt.create_order('ORD-T006', 1001, NULL)")
    assert scalar(cur, "SELECT pkg_order_mgmt.g_call_count()") == 1
    conn.rollback()
    assert scalar(cur, "SELECT pkg_order_mgmt.g_call_count()") == 0


def test_duplicate_order_number_raises_mapped_error_and_rolls_back(conn, cur):
    """DUP_VAL_ON_INDEX plus ROLLBACK TO before_order.

    The Oracle savepoint is the PL/pgSQL exception block: the failed INSERT is
    undone but earlier work in the caller's transaction survives.
    """
    marker_id = scalar(cur, "SELECT pkg_order_mgmt.create_order('ORD-T007', 1001, NULL)")

    before = scalar(cur, "SELECT count(*) FROM retail.orders")
    with pytest.raises(psycopg.Error) as excinfo, conn.transaction():
        cur.execute("SELECT pkg_order_mgmt.create_order('ORD-5001', 1001, NULL)")
    assert excinfo.value.sqlstate == "OR901"
    assert "Order number already exists" in str(excinfo.value)

    assert scalar(cur, "SELECT count(*) FROM retail.orders") == before
    assert scalar(
        cur, "SELECT count(*) FROM retail.orders WHERE order_id = %s", (marker_id,)
    ) == 1, "work before the failed call survived, like ROLLBACK TO savepoint"


def test_add_order_line_assigns_next_line_number(cur):
    order_id = scalar(cur, "SELECT pkg_order_mgmt.create_order('ORD-T008', 1001, NULL)")
    assert scalar(
        cur, "SELECT pkg_order_mgmt.add_order_line(%s, 3001, 2, 10.00)", (order_id,)
    ) == 1
    assert scalar(
        cur, "SELECT pkg_order_mgmt.add_order_line(%s, 3003, 1, 99.99)", (order_id,)
    ) == 2
    assert [r[0] for r in rows(
        cur,
        "SELECT line_number FROM retail.order_lines WHERE order_id = %s ORDER BY 1",
        (order_id,),
    )] == [1, 2]


def test_add_order_line_updates_totals_with_tax(cur):
    order_id = scalar(cur, "SELECT pkg_order_mgmt.create_order('ORD-T009', 1001, NULL)")
    cur.execute("SELECT pkg_order_mgmt.add_order_line(%s, 3001, 2, 10.00)", (order_id,))
    subtotal, discount, tax, total = one(
        cur,
        "SELECT subtotal_amount, discount_amount, tax_amount, total_amount"
        " FROM retail.orders WHERE order_id = %s",
        (order_id,),
    )
    assert (subtotal, discount) == (20, 0)
    assert tax == dec("1.65"), "round(20 * 0.0825, 2)"
    assert total == dec("21.65")


def test_add_order_line_defaults_null_quantity_to_one(cur):
    order_id = scalar(cur, "SELECT pkg_order_mgmt.create_order('ORD-T010', 1001, NULL)")
    cur.execute(
        "SELECT pkg_order_mgmt.add_order_line(%s, 3001, NULL, 10.00)", (order_id,)
    )
    quantity, extended = one(
        cur,
        "SELECT quantity, extended_amount FROM retail.order_lines"
        " WHERE order_id = %s AND line_number = 1",
        (order_id,),
    )
    assert (quantity, extended) == (1, 10)


def test_refresh_order_total_applies_line_discount(cur):
    """Seeded order 5001 has a 10 percent discount on a 99.99 line."""
    cur.execute("SELECT pkg_order_mgmt.refresh_order_total(5001)")
    subtotal, discount, tax, total = one(
        cur,
        "SELECT subtotal_amount, discount_amount, tax_amount, total_amount"
        " FROM retail.orders WHERE order_id = 5001",
    )
    assert subtotal == dec("119.99")
    assert discount == dec("10.00"), "9.999 rounded into NUMBER(14,2)"
    assert tax == dec("9.07")
    assert total == dec("119.06")


def test_refresh_order_total_handles_null_extended_amount(cur):
    """Order 5002 has one line with a NULL extended_amount."""
    cur.execute("SELECT pkg_order_mgmt.refresh_order_total(5002)")
    subtotal, discount, tax, total = one(
        cur,
        "SELECT subtotal_amount, discount_amount, tax_amount, total_amount"
        " FROM retail.orders WHERE order_id = 5002",
    )
    assert (subtotal, discount, tax, total) == (0, 0, 0, 0)


def test_refresh_order_total_on_order_without_lines(cur):
    cur.execute("SELECT pkg_order_mgmt.refresh_order_total(5004)")
    assert scalar(
        cur, "SELECT total_amount FROM retail.orders WHERE order_id = 5004"
    ) == 0


def test_fractional_quantity_survives_numeric_mapping(cur):
    quantity, extended = one(
        cur,
        "SELECT quantity, extended_amount FROM retail.order_lines"
        " WHERE order_id = 5005 AND line_number = 1",
    )
    assert quantity == dec("2.5")
    assert extended == dec("25.00")


def test_list_customer_orders_paginates_like_rownum_version(cur):
    """ROWNUM windowing became LIMIT and OFFSET. Customer 1002 has six orders."""
    page1 = rows(cur, "SELECT * FROM pkg_order_mgmt.list_customer_orders(1002, 1, 2)")
    page2 = rows(cur, "SELECT * FROM pkg_order_mgmt.list_customer_orders(1002, 2, 2)")
    page3 = rows(cur, "SELECT * FROM pkg_order_mgmt.list_customer_orders(1002, 3, 2)")
    page4 = rows(cur, "SELECT * FROM pkg_order_mgmt.list_customer_orders(1002, 4, 2)")

    assert [r[0] for r in page1] == [5010, 5009]
    assert [r[0] for r in page2] == [5008, 5007]
    assert [r[0] for r in page3] == [5006, 5005]
    assert page4 == []


def test_list_customer_orders_defaults_page_arguments(cur):
    all_rows = rows(cur, "SELECT * FROM pkg_order_mgmt.list_customer_orders(1002)")
    assert [r[0] for r in all_rows] == [5010, 5009, 5008, 5007, 5006, 5005]

    explicit_nulls = rows(
        cur, "SELECT * FROM pkg_order_mgmt.list_customer_orders(1002, NULL, NULL)"
    )
    assert [r[0] for r in explicit_nulls] == [r[0] for r in all_rows]


def test_list_customer_orders_for_customer_without_orders(cur):
    assert rows(cur, "SELECT * FROM pkg_order_mgmt.list_customer_orders(1007, 1, 25)") == []


def test_load_order_totals_uses_session_temp_table(conn, cur):
    """Global temporary table replacement, plus BULK COLLECT and FORALL folded
    into one set based INSERT."""
    loaded = scalar(cur, "SELECT pkg_order_mgmt.load_order_totals(1002)")
    assert loaded == 6

    gtt = rows(
        cur,
        "SELECT order_id, line_count, calculated_total FROM gtt_order_totals ORDER BY order_id",
    )
    assert [r[0] for r in gtt] == [5005, 5006, 5007, 5008, 5009, 5010]
    assert gtt[0][1] == 1, "order 5005 has one line"
    assert gtt[1][1] == 0, "order 5006 has none"
    assert gtt[0][2] == dec("27.06")

    # ON COMMIT DELETE ROWS, same lifetime as the Oracle GTT
    conn.commit()
    assert scalar(cur, "SELECT count(*) FROM gtt_order_totals") == 0


def test_load_order_totals_for_customer_without_orders(cur):
    assert scalar(cur, "SELECT pkg_order_mgmt.load_order_totals(1007)") == 0


def test_load_order_totals_error_is_mapped(conn, cur):
    """The exception block replaces SAVEPOINT before_totals plus ROLLBACK TO.

    Failure is forced by putting a temp table of the wrong shape in the way, so
    the INSERT inside the function cannot succeed.
    """
    with pytest.raises(psycopg.Error) as excinfo, conn.transaction():
        cur.execute("CREATE TEMP TABLE gtt_order_totals (order_id bigint)")
        cur.execute("SELECT pkg_order_mgmt.load_order_totals(1002)")
    assert excinfo.value.sqlstate == "OR902"
    assert "Could not load order totals" in str(excinfo.value)

    # the caller's transaction is usable afterwards
    assert scalar(cur, "SELECT 1") == 1


def test_summarize_order_counts_lines_and_reverse_loop_marker(cur):
    line_count, marker, unpriced, invoice_label = one(
        cur, "SELECT * FROM pkg_order_mgmt.summarize_order(5001)"
    )
    assert line_count == 2
    # FOR i IN REVERSE 1..2 leaves i = 1 on the last iteration
    assert marker == "LINE-1"
    assert unpriced == 0
    assert invoice_label == "order=5001 invoice=6001"


def test_summarize_order_reports_null_amount_line(cur):
    line_count, marker, unpriced, invoice_label = one(
        cur, "SELECT * FROM pkg_order_mgmt.summarize_order(5002)"
    )
    assert (line_count, marker, unpriced) == (1, "LINE-1", 1)
    # (+) outer join: the row must come back with no invoice
    assert invoice_label == "order=5002 invoice=NONE"


def test_summarize_order_with_no_lines_still_returns_marker(cur):
    line_count, marker, unpriced, invoice_label = one(
        cur, "SELECT * FROM pkg_order_mgmt.summarize_order(5004)"
    )
    # GREATEST(l_line_count, 1) keeps the loop running once
    assert (line_count, marker, unpriced) == (0, "LINE-1", 0)
    assert invoice_label == "order=5004 invoice=6003"


def test_summarize_order_for_missing_order(cur):
    assert one(cur, "SELECT * FROM pkg_order_mgmt.summarize_order(999999)") == (
        0,
        "LINE-1",
        0,
        None,
    )


def test_dynamic_sql_uses_quoted_identifiers(cur):
    """create_order builds its lookup with format() and %I. A schema qualified
    identifier that would break plain concatenation still works."""
    order_id = scalar(cur, "SELECT pkg_order_mgmt.create_order('ORD-T011', 1001, NULL)")
    assert scalar(cur, "SELECT pkg_order_mgmt.g_last_order_id()") == order_id


def test_functions_are_schema_qualified(cur):
    found = {
        (schema, name)
        for schema, name in rows(
            cur,
            """
            SELECT n.nspname, p.proname
            FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'pkg_order_mgmt'
            """,
        )
    }
    expected = {
        ("pkg_order_mgmt", name)
        for name in (
            "create_order",
            "add_order_line",
            "refresh_order_total",
            "list_customer_orders",
            "load_order_totals",
            "summarize_order",
            "g_call_count",
            "g_last_order_id",
            "reset_package_state",
        )
    }
    assert expected <= found
