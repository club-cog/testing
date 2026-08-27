"""PostgreSQL DAO, converted from dao.py.

The Oracle version is left in place unchanged so the two can be read side by
side. Mapping used here:

    oracledb.connect(dsn=...)      -> psycopg.connect(conninfo)
    cursor.callproc(PKG.PROC, ...) -> SELECT schema.function(...)
    OUT parameter via cursor.var   -> the function's return value
    SYS_REFCURSOR OUT parameter    -> SELECT * FROM schema.function(...)
    :bind names                    -> %(name)s
    NVL and (+)                    -> COALESCE and LEFT JOIN

One conversion trap worth naming: psycopg infers PostgreSQL types from Python
types, so a small int arrives as smallint and a float as double precision, and
function resolution then fails to find the bigint and numeric signatures. Every
placeholder that feeds a function argument is cast explicitly below. Oracle did
not care, because PL/SQL NUMBER accepted anything numeric.

Connection settings come from the environment. No credentials are stored in
this file, and nothing here talks to Oracle.
"""

from __future__ import annotations

import os
from collections.abc import Sequence
from decimal import Decimal
from typing import Any

import psycopg

DEFAULT_CONNINFO = "postgresql://demo:demo@127.0.0.1:55432/oracle_migration_demo"


def conninfo() -> str:
    return os.environ.get("DATABASE_URL", DEFAULT_CONNINFO)


class PostgresConnection:
    """Replacement for LegacyConnection.

    psycopg connections start a transaction on first execute and hold it until
    commit or rollback, which is the same shape the Oracle workers assumed.
    autocommit is left off on purpose: the converted functions rely on the
    caller's transaction for the savepoint semantics that Oracle got from
    SAVEPOINT and ROLLBACK TO.
    """

    def __init__(self, connection: psycopg.Connection | None = None) -> None:
        self.connection = connection

    def connect(self) -> psycopg.Connection:
        if self.connection is None:
            self.connection = psycopg.connect(conninfo(), autocommit=False)
        return self.connection

    def close(self) -> None:
        if self.connection is not None:
            self.connection.close()
            self.connection = None


class OrderDao:
    """PKG_ORDER_MGMT calls against schema pkg_order_mgmt."""

    def __init__(self, connection: psycopg.Connection) -> None:
        self.connection = connection

    def create_order(
        self, order_number: str, customer_id: int, requested_by: str | None
    ) -> int:
        with self.connection.cursor() as cursor:
            cursor.execute(
                "SELECT pkg_order_mgmt.create_order(%s::varchar, %s::bigint, %s::varchar)",
                (order_number, customer_id, requested_by),
            )
            row = cursor.fetchone()
        assert row is not None
        return row[0]

    def add_line(
        self,
        order_id: int,
        product_id: int,
        quantity: Decimal | int | None,
        unit_price: Decimal | float,
    ) -> Decimal:
        """Returns the assigned line number.

        The Oracle procedure had no OUT parameter, so callers had to re-query.
        The converted function returns it directly.
        """
        with self.connection.cursor() as cursor:
            cursor.execute(
                "SELECT pkg_order_mgmt.add_order_line(%s::bigint, %s::bigint,"
                " %s::numeric, %s::numeric)",
                (order_id, product_id, quantity, unit_price),
            )
            row = cursor.fetchone()
        self.connection.commit()
        assert row is not None
        return row[0]

    def refresh_total(self, order_id: int) -> None:
        with self.connection.cursor() as cursor:
            cursor.execute(
                "SELECT pkg_order_mgmt.refresh_order_total(%s::bigint)", (order_id,)
            )
        self.connection.commit()

    def page_for_customer(
        self, customer_id: int, page_number: int = 1, page_size: int = 25
    ) -> list[tuple[Any, ...]]:
        """The SYS_REFCURSOR OUT parameter became a set returning function, so
        the result is read straight out of a SELECT."""
        with self.connection.cursor() as cursor:
            cursor.execute(
                "SELECT * FROM pkg_order_mgmt.list_customer_orders(%s::bigint,"
                " %s::integer, %s::integer)",
                (customer_id, page_number, page_size),
            )
            return cursor.fetchall()

    def load_totals_for_customer(self, customer_id: int) -> list[tuple[Any, ...]]:
        """Fills the session temp table that replaced the Oracle GTT.

        The rows only exist for the current transaction (ON COMMIT DELETE ROWS),
        so the read has to happen before any commit.
        """
        with self.connection.cursor() as cursor:
            cursor.execute(
                "SELECT pkg_order_mgmt.load_order_totals(%s::bigint)", (customer_id,)
            )
            cursor.execute(
                "SELECT order_id, line_count, calculated_total"
                " FROM gtt_order_totals ORDER BY order_id"
            )
            return cursor.fetchall()

    def summarize(self, order_id: int) -> tuple[Any, ...] | None:
        with self.connection.cursor() as cursor:
            cursor.execute(
                "SELECT * FROM pkg_order_mgmt.summarize_order(%s::bigint)", (order_id,)
            )
            return cursor.fetchone()

    def summary_query(self, customer_id: int) -> list[tuple[Any, ...]]:
        """Converted from old_summary_query.

        The comma join with (+) becomes an explicit LEFT JOIN, NVL becomes
        COALESCE, and the named bind changes syntax. Same rows, same order.
        """
        with self.connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT o.order_number, COALESCE(i.invoice_status, 'UNBILLED')
                FROM retail.orders o
                LEFT JOIN retail.invoices i ON o.order_id = i.order_id
                WHERE o.customer_id = %(customer_id)s
                ORDER BY o.ordered_at DESC, o.order_id DESC
                """,
                {"customer_id": customer_id},
            )
            return cursor.fetchall()

    def call_count(self) -> int:
        """Package state accessor.

        Reads the session GUC that replaced the package variable. Note the
        difference from Oracle: a rollback also undoes this counter.
        """
        with self.connection.cursor() as cursor:
            cursor.execute("SELECT pkg_order_mgmt.g_call_count()")
            row = cursor.fetchone()
        assert row is not None
        return row[0]


class BillingDao:
    """PKG_BILLING calls against schema pkg_billing."""

    def __init__(self, connection: psycopg.Connection) -> None:
        self.connection = connection

    def issue_invoice(self, order_id: int) -> int:
        with self.connection.cursor() as cursor:
            cursor.execute("SELECT pkg_billing.issue_invoice(%s::bigint)", (order_id,))
            row = cursor.fetchone()
        self.connection.commit()
        assert row is not None
        return row[0]

    def take_payment(
        self, invoice_id: int, amount: Decimal | float, method: str | None
    ) -> str:
        """Returns the resulting invoice status, which the Oracle procedure only
        wrote to DBMS_OUTPUT."""
        with self.connection.cursor() as cursor:
            cursor.execute(
                "SELECT pkg_billing.apply_payment(%s::bigint, %s::numeric, %s::varchar)",
                (invoice_id, amount, method),
            )
            row = cursor.fetchone()
        self.connection.commit()
        assert row is not None
        return row[0]

    def rebuild_totals(self, invoice_id: int) -> Decimal:
        with self.connection.cursor() as cursor:
            cursor.execute(
                "SELECT pkg_billing.rebuild_invoice_totals(%s::bigint)", (invoice_id,)
            )
            row = cursor.fetchone()
        self.connection.commit()
        assert row is not None
        return row[0]

    def log(self, entity_id: int, action_code: str, payload: str) -> None:
        """The Oracle procedure was PRAGMA AUTONOMOUS_TRANSACTION and committed
        on its own. Here the row is part of the caller's transaction, so it
        disappears if the caller rolls back. See CONVERSION-NOTES.md."""
        with self.connection.cursor() as cursor:
            cursor.execute(
                "SELECT pkg_billing.write_billing_log(%s::bigint, %s::varchar, %s::text)",
                (entity_id, action_code, payload),
            )


class HierarchyDao:
    """PKG_CUSTOMER_HIER calls. There was no Oracle DAO for this package; the
    application built the CONNECT BY query inline."""

    def __init__(self, connection: psycopg.Connection) -> None:
        self.connection = connection

    def tree(self, root_customer_id: int) -> list[tuple[Any, ...]]:
        return self._fetch(
            "SELECT * FROM pkg_customer_hier.print_tree(%s::bigint)", (root_customer_id,)
        )

    def ancestors(self, customer_id: int) -> list[tuple[Any, ...]]:
        return self._fetch(
            "SELECT * FROM pkg_customer_hier.list_ancestors(%s::bigint)", (customer_id,)
        )

    def unordered_customers(self) -> list[tuple[Any, ...]]:
        return self._fetch("SELECT * FROM pkg_customer_hier.find_unordered_customers()")

    def descendant_count(self, root_customer_id: int) -> int:
        rows = self._fetch(
            "SELECT pkg_customer_hier.descendant_count(%s::bigint)", (root_customer_id,)
        )
        return rows[0][0]

    def _fetch(self, sql: str, params: Sequence[Any] | None = None) -> list[tuple[Any, ...]]:
        with self.connection.cursor() as cursor:
            cursor.execute(sql, params)
            return cursor.fetchall()
