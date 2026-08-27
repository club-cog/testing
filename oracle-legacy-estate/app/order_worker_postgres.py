"""Converted batch worker. The Oracle version in order_worker.py is unchanged.

Only two things differ from the Oracle worker: the imports point at
dao_postgres, and the payment step reads the returned invoice status instead of
scraping DBMS_OUTPUT. The call sequence is identical, which is the point: the
application-side change for this worker is an import swap plus a return value.
"""

from __future__ import annotations

from typing import Any

from .dao_postgres import BillingDao, OrderDao, PostgresConnection


def process_order(connection, payload: dict[str, Any]) -> tuple[int, int, str | None]:
    order_dao = OrderDao(connection)
    billing_dao = BillingDao(connection)

    order_id = order_dao.create_order(
        payload["order_number"],
        payload["customer_id"],
        payload.get("requested_by"),
    )

    for line in payload.get("lines", []):
        order_dao.add_line(
            order_id,
            line["product_id"],
            line.get("quantity", 1),
            line["unit_price"],
        )

    invoice_id = billing_dao.issue_invoice(order_id)

    invoice_status = None
    if payload.get("payment"):
        invoice_status = billing_dao.take_payment(
            invoice_id,
            payload["payment"]["amount"],
            payload["payment"].get("method"),
        )
    return order_id, invoice_id, invoice_status


def fetch_page(connection, customer_id: int, page: int) -> list[tuple[Any, ...]]:
    return OrderDao(connection).page_for_customer(
        customer_id=customer_id,
        page_number=page,
        page_size=25,
    )


def run_placeholder_batch() -> list[tuple[Any, ...]]:
    """Same scheduler entry point, now against PostgreSQL."""
    holder = PostgresConnection()
    try:
        connection = holder.connect()
        return fetch_page(connection, 1001, 1)
    finally:
        holder.close()
