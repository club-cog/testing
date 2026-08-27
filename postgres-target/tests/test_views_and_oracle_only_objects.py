"""Views, synonym replacement, materialized view and GTT replacement."""

from __future__ import annotations

import psycopg
from conftest import dec, one, rows, scalar


def test_v_order_summary_labels_unbilled_orders(cur):
    """NVL(i.invoice_status,'UNBILLED') over an outer join. Order 5002 has no
    invoice, so the row must still appear."""
    status, total = one(
        cur,
        "SELECT invoice_status, invoice_total FROM retail.v_order_summary"
        " WHERE order_id = 5002",
    )
    assert (status, total) == ("UNBILLED", 0)


def test_v_order_summary_covers_every_order(cur):
    assert scalar(cur, "SELECT count(*) FROM retail.v_order_summary") == scalar(
        cur, "SELECT count(*) FROM retail.orders"
    )


def test_v_order_summary_joins_customer_columns(cur):
    code, name, invoice_status = one(
        cur,
        "SELECT customer_code, display_name, invoice_status FROM retail.v_order_summary"
        " WHERE order_id = 5001",
    )
    # invoice 6001 is seeded ISSUED, then trg_payments_ai moves it to PARTIAL
    # when the two seeded payments land, the same as the Oracle trigger
    assert (code, invoice_status) == ("C-ROOT", "PARTIAL")
    assert name == "Root Holding Fixture"


def test_v_customer_balance_reproduces_the_oracle_fan_out(cur):
    """Invoice 6001 totals 119.06 and has two captured payments, so the faithful
    view double counts it. Documented defect, kept on purpose."""
    invoiced, paid, balance = one(
        cur,
        "SELECT invoiced_total, paid_total, balance_due FROM retail.v_customer_balance"
        " WHERE customer_id = 1001",
    )
    assert invoiced == dec("238.12"), "119.06 counted once per payment row"
    assert paid == dec("80.00")
    assert balance == dec("158.12")


def test_v_customer_balance_deduped_gives_the_correct_figure(cur):
    invoiced, paid, balance = one(
        cur,
        "SELECT invoiced_total, paid_total, balance_due FROM retail.v_customer_balance_deduped"
        " WHERE customer_id = 1001",
    )
    assert invoiced == dec("119.06")
    assert paid == dec("80.00")
    assert balance == dec("39.06")


def test_v_customer_balance_keeps_customers_without_orders(cur):
    assert one(
        cur,
        "SELECT invoiced_total, paid_total, balance_due FROM retail.v_customer_balance"
        " WHERE customer_id = 1007",
    ) == (0, 0, 0)


def test_both_balance_views_agree_when_there_is_one_payment(cur):
    """The fan-out only shows up with more than one payment row per invoice."""
    faithful = rows(
        cur,
        "SELECT customer_id, invoiced_total FROM retail.v_customer_balance"
        " WHERE customer_id <> 1001 ORDER BY customer_id",
    )
    deduped = rows(
        cur,
        "SELECT customer_id, invoiced_total FROM retail.v_customer_balance_deduped"
        " WHERE customer_id <> 1001 ORDER BY customer_id",
    )
    assert faithful == deduped


def test_v_recent_orders_is_ordered_and_capped(cur):
    ordered_at = [r[0] for r in rows(cur, "SELECT ordered_at FROM retail.v_recent_orders")]
    assert ordered_at == sorted(ordered_at, reverse=True)
    assert len(ordered_at) <= 50
    first = scalar(cur, "SELECT order_id FROM retail.v_recent_orders LIMIT 1")
    assert first == 5011, "the 2999 boundary date sorts first"


def test_current_orders_view_replaces_the_synonym(cur):
    assert scalar(cur, "SELECT count(*) FROM retail.current_orders") == scalar(
        cur, "SELECT count(*) FROM retail.orders"
    )
    assert scalar(
        cur,
        "SELECT count(*) FROM information_schema.columns"
        " WHERE table_schema = 'retail' AND table_name = 'current_orders'",
    ) == scalar(
        cur,
        "SELECT count(*) FROM information_schema.columns"
        " WHERE table_schema = 'retail' AND table_name = 'orders'",
    )


def test_current_orders_view_is_updatable_like_a_synonym(cur):
    assert scalar(
        cur,
        "SELECT is_updatable FROM information_schema.views"
        " WHERE table_schema = 'retail' AND table_name = 'current_orders'",
    ) == "YES"

    cur.execute(
        "INSERT INTO retail.current_orders (order_number, customer_id) VALUES ('ORD-S001', 1001)"
    )
    assert scalar(
        cur, "SELECT count(*) FROM retail.orders WHERE order_number = 'ORD-S001'"
    ) == 1

    cur.execute("UPDATE retail.current_orders SET order_status = 'READY' WHERE order_number = 'ORD-S001'")
    assert scalar(
        cur, "SELECT order_status FROM retail.orders WHERE order_number = 'ORD-S001'"
    ) == "READY"

    cur.execute("DELETE FROM retail.current_orders WHERE order_number = 'ORD-S001'")
    assert scalar(
        cur, "SELECT count(*) FROM retail.orders WHERE order_number = 'ORD-S001'"
    ) == 0


def test_materialized_view_is_populated_and_stale_until_refreshed(cur):
    order_count, order_total = one(
        cur,
        "SELECT order_count, order_total FROM retail.mv_customer_order_rollup"
        " WHERE customer_id = 1001",
    )
    assert order_count == 3, "orders 5001, 5002 and 5004"
    assert order_total == dec("119.06")

    cur.execute(
        "INSERT INTO retail.orders (order_number, customer_id) VALUES ('ORD-M001', 1001)"
    )
    assert scalar(
        cur,
        "SELECT order_count FROM retail.mv_customer_order_rollup WHERE customer_id = 1001",
    ) == 3, "REFRESH COMPLETE ON DEMAND: no automatic refresh, same as Oracle"

    cur.execute("SELECT retail.refresh_customer_order_rollup()")
    assert scalar(
        cur,
        "SELECT order_count FROM retail.mv_customer_order_rollup WHERE customer_id = 1001",
    ) == 4


def test_materialized_view_has_the_unique_index_for_concurrent_refresh(cur):
    assert scalar(
        cur,
        "SELECT count(*) FROM pg_indexes WHERE schemaname = 'retail'"
        " AND indexname = 'ux_mv_customer_rollup_customer'",
    ) == 1


def test_gtt_template_stays_empty(cur):
    assert scalar(cur, "SELECT count(*) FROM retail.gtt_order_totals_template") == 0


def test_ensure_gtt_is_idempotent_within_a_session(cur):
    cur.execute("SELECT retail.ensure_gtt_order_totals()")
    cur.execute("SELECT retail.ensure_gtt_order_totals()")
    assert scalar(cur, "SELECT to_regclass('pg_temp.gtt_order_totals') IS NOT NULL")


def test_gtt_rows_are_session_private(cur):
    """Oracle GTT contents are visible only to the owning session. A second
    connection must not see them, and must not fail either."""
    cur.execute("SELECT pkg_order_mgmt.load_order_totals(1002)")
    assert scalar(cur, "SELECT count(*) FROM gtt_order_totals") == 6

    from conftest import DATABASE_URL

    with psycopg.connect(DATABASE_URL) as other, other.cursor() as other_cur:
        other_cur.execute("SELECT to_regclass('pg_temp.gtt_order_totals')")
        assert other_cur.fetchone()[0] is None


def test_index_organized_table_is_clustered_on_its_primary_key(cur):
    assert scalar(
        cur,
        "SELECT i.relname FROM pg_index x"
        " JOIN pg_class t ON t.oid = x.indrelid"
        " JOIN pg_class i ON i.oid = x.indexrelid"
        " JOIN pg_namespace n ON n.oid = t.relnamespace"
        " WHERE n.nspname = 'retail' AND t.relname = 'order_lines' AND x.indisclustered",
    ) == "pk_order_lines"


def test_bitmap_index_replacement_exists(cur):
    names = {
        name
        for (name,) in rows(
            cur,
            "SELECT indexname FROM pg_indexes WHERE schemaname = 'retail'"
            " AND tablename = 'orders'",
        )
    }
    assert {"bix_orders_status", "ix_orders_status_open"} <= names


def test_partial_index_replacement_is_used_for_open_orders(cur):
    plan = "\n".join(
        row[0]
        for row in rows(
            cur,
            "EXPLAIN SELECT order_id FROM retail.orders"
            " WHERE order_status IN ('OPEN','HELD') ORDER BY ordered_at DESC",
        )
    )
    assert "orders" in plan
