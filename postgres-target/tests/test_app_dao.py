"""The converted application tier, exercised against the same database.

This covers workstream three: every place the application talked to Oracle.
The DAO under test is oracle-legacy-estate/app/dao_postgres.py. The Oracle DAO
is not imported, because importing it would require an Oracle driver and there
is no Oracle instance in this environment by design.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest
from conftest import DATABASE_URL, dec, rebuild_module

REPO_ROOT = Path(__file__).resolve().parents[2]
APP_DIR = REPO_ROOT / "oracle-legacy-estate" / "app"


def _load(module_name: str):
    """Load one module out of the legacy app package without importing dao.py.

    order_worker_postgres uses a relative import, so the package has to exist in
    sys.modules first, but only the PostgreSQL modules are executed.
    """
    package = "legacy_app"
    if package not in sys.modules:
        spec = importlib.util.spec_from_file_location(
            package, APP_DIR / "__init__.py", submodule_search_locations=[str(APP_DIR)]
        )
        module = importlib.util.module_from_spec(spec)
        sys.modules[package] = module
        spec.loader.exec_module(module)
    return importlib.import_module(f"{package}.{module_name}")


dao_postgres = _load("dao_postgres")
worker = _load("order_worker_postgres")


@pytest.fixture()
def dao_connection(monkeypatch):
    """A real DAO connection.

    The DAO commits, exactly as the deployed worker does, so the usual
    rollback-per-test trick does not apply here. The seeded state is restored by
    rebuilding after each test instead, which keeps these tests honest about the
    commits and keeps the rest of the suite reading pristine fixture data.
    """
    monkeypatch.setenv("DATABASE_URL", DATABASE_URL)
    holder = dao_postgres.PostgresConnection()
    connection = holder.connect()
    try:
        yield connection
    finally:
        connection.rollback()
        holder.close()
        rebuild_module.rebuild(DATABASE_URL, quiet=True)


def test_connection_wrapper_reads_the_environment(monkeypatch):
    monkeypatch.setenv("DATABASE_URL", DATABASE_URL)
    assert dao_postgres.conninfo() == DATABASE_URL
    monkeypatch.delenv("DATABASE_URL")
    assert dao_postgres.conninfo() == dao_postgres.DEFAULT_CONNINFO
    assert "127.0.0.1" in dao_postgres.DEFAULT_CONNINFO


def test_order_dao_create_and_add_line(dao_connection):
    dao = dao_postgres.OrderDao(dao_connection)
    order_id = dao.create_order("ORD-D001", 1001, None)
    assert order_id > 5012

    assert dao.add_line(order_id, 3001, 2, 10.00) == 1
    assert dao.add_line(order_id, 3003, 1, 99.99) == 2

    with dao_connection.cursor() as cursor:
        cursor.execute(
            "SELECT total_amount FROM retail.orders WHERE order_id = %s", (order_id,)
        )
        # 2 * 10.00 + 1 * 99.99 = 119.99, tax round(119.99 * 0.0825, 2) = 9.90
        assert cursor.fetchone()[0] == dec("129.89")


def test_order_dao_pagination_matches_the_function(dao_connection):
    dao = dao_postgres.OrderDao(dao_connection)
    assert [row[0] for row in dao.page_for_customer(1002, 1, 2)] == [5010, 5009]
    assert [row[0] for row in dao.page_for_customer(1002, 3, 2)] == [5006, 5005]
    assert dao.page_for_customer(1002, 9, 2) == []


def test_order_dao_summary_query_replaces_the_plus_join(dao_connection):
    dao = dao_postgres.OrderDao(dao_connection)
    found = dao.summary_query(1001)
    assert ("ORD-5002", "UNBILLED") in found
    assert ("ORD-5001", "PARTIAL") in found
    assert len(found) == 3


def test_order_dao_reads_the_gtt_before_commit(dao_connection):
    dao = dao_postgres.OrderDao(dao_connection)
    loaded = dao.load_totals_for_customer(1002)
    assert [row[0] for row in loaded] == [5005, 5006, 5007, 5008, 5009, 5010]
    assert loaded[0][2] == dec("27.06")


def test_order_dao_exposes_package_state(dao_connection):
    dao = dao_postgres.OrderDao(dao_connection)
    before = dao.call_count()
    dao.create_order("ORD-D002", 1001, None)
    assert dao.call_count() == before + 1


def test_order_dao_summarize(dao_connection):
    dao = dao_postgres.OrderDao(dao_connection)
    assert dao.summarize(5001) == (2, "LINE-1", 0, "order=5001 invoice=6001")


def test_billing_dao_issue_and_pay(dao_connection):
    order_dao = dao_postgres.OrderDao(dao_connection)
    billing_dao = dao_postgres.BillingDao(dao_connection)

    order_id = order_dao.create_order("ORD-D003", 1001, None)
    order_dao.add_line(order_id, 3001, 1, 100.00)

    invoice_id = billing_dao.issue_invoice(order_id)
    assert billing_dao.take_payment(invoice_id, 1.00, "CARD") == "PARTIAL"
    assert billing_dao.take_payment(invoice_id, 200.00, "ACH") == "PAID"
    assert billing_dao.rebuild_totals(invoice_id) == 0, "no invoice lines yet"


def test_billing_dao_log_helper(dao_connection):
    billing_dao = dao_postgres.BillingDao(dao_connection)
    billing_dao.log(6001, "DAO", "written by the converted DAO")
    with dao_connection.cursor() as cursor:
        cursor.execute(
            "SELECT payload FROM retail.audit_log WHERE entity_id = 6001 AND action_code = 'DAO'"
        )
        assert cursor.fetchone()[0] == "written by the converted DAO"


def test_hierarchy_dao(dao_connection):
    dao = dao_postgres.HierarchyDao(dao_connection)
    assert [row[0] for row in dao.tree(1001)] == [1001, 1002, 1004, 1005, 1006, 1003]
    assert [row[0] for row in dao.ancestors(1006)] == [1006, 1005, 1004, 1002, 1001]
    assert dao.descendant_count(1001) == 6
    assert 1007 not in [row[0] for row in dao.unordered_customers()]


def test_worker_runs_the_whole_flow(dao_connection):
    order_id, invoice_id, invoice_status = worker.process_order(
        dao_connection,
        {
            "order_number": "ORD-D004",
            "customer_id": 1001,
            "lines": [
                {"product_id": 3001, "quantity": 2, "unit_price": 10.00},
                {"product_id": 3003, "unit_price": 99.99},
            ],
            "payment": {"amount": 50.00, "method": "CARD"},
        },
    )
    assert order_id > 5012
    assert invoice_id > 6003
    assert invoice_status == "PARTIAL"

    with dao_connection.cursor() as cursor:
        cursor.execute(
            "SELECT invoice_total, invoice_status FROM retail.invoices WHERE invoice_id = %s",
            (invoice_id,),
        )
        assert cursor.fetchone() == (dec("129.89"), "PARTIAL")


def test_worker_fetch_page(dao_connection):
    assert [row[0] for row in worker.fetch_page(dao_connection, 1002, 1)][:2] == [
        5010,
        5009,
    ]
