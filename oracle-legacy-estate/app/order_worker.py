"""Invented batch worker showing application-side Oracle references."""

from .dao import BillingDao, LegacyConnection, OrderDao


def process_order(connection, payload):
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
    if payload.get("payment"):
        billing_dao.take_payment(
            invoice_id,
            payload["payment"]["amount"],
            payload["payment"].get("method"),
        )
    return order_id, invoice_id


def fetch_page(connection, customer_id, page):
    return OrderDao(connection).page_for_customer(
        customer_id=customer_id,
        page_number=page,
        page_size=25,
    )


def run_placeholder_batch():
    """Call site retained for an old scheduler entry."""
    holder = LegacyConnection()
    try:
        connection = holder.connect()
        # The scheduler injects real payloads in the deployed estate.
        return fetch_page(connection, 1001, 1)
    finally:
        holder.close()
