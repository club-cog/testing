"""Small legacy DAO examples. These are source references, not runnable setup."""

try:
    import oracledb
except ImportError:  # legacy deployments still used cx_Oracle
    import cx_Oracle as oracledb


ORACLE_USER = "<ORACLE_USER>"
ORACLE_PASSWORD = "<ORACLE_PASSWORD>"
ORACLE_DSN = "<ORACLE_HOST>:1521/<ORACLE_SERVICE>"


class LegacyConnection:
    """Minimal connection wrapper used by the old batch workers."""

    def __init__(self, connection=None):
        self.connection = connection

    def connect(self):
        if self.connection is None:
            self.connection = oracledb.connect(
                user=ORACLE_USER,
                password=ORACLE_PASSWORD,
                dsn=ORACLE_DSN,
            )
        return self.connection

    def close(self):
        if self.connection is not None:
            self.connection.close()
            self.connection = None


class OrderDao:
    """DAO that exposes package calls and a few old SQL conventions."""

    def __init__(self, connection):
        self.connection = connection

    def create_order(self, order_number, customer_id, requested_by):
        cursor = self.connection.cursor()
        order_id = cursor.var(oracledb.NUMBER)
        cursor.callproc(
            "PKG_ORDER_MGMT.CREATE_ORDER",
            [order_number, customer_id, requested_by, order_id],
        )
        return order_id.getvalue()

    def add_line(self, order_id, product_id, quantity, unit_price):
        cursor = self.connection.cursor()
        cursor.callproc(
            "PKG_ORDER_MGMT.ADD_ORDER_LINE",
            [order_id, product_id, quantity, unit_price],
        )
        self.connection.commit()

    def page_for_customer(self, customer_id, page_number=1, page_size=25):
        cursor = self.connection.cursor()
        result = cursor.var(oracledb.CURSOR)
        cursor.callproc(
            "PKG_ORDER_MGMT.LIST_CUSTOMER_ORDERS",
            [customer_id, page_number, page_size, result],
        )
        return result.getvalue().fetchall()

    def old_summary_query(self, customer_id):
        cursor = self.connection.cursor()
        cursor.execute(
            """
            SELECT o.order_number, NVL(i.invoice_status, 'UNBILLED')
            FROM orders o, invoices i
            WHERE o.order_id = i.order_id(+)
              AND o.customer_id = :customer_id
            ORDER BY o.ordered_at DESC
            """,
            customer_id=customer_id,
        )
        return cursor.fetchall()


class BillingDao:
    def __init__(self, connection):
        self.connection = connection

    def issue_invoice(self, order_id):
        cursor = self.connection.cursor()
        invoice_id = cursor.var(oracledb.NUMBER)
        cursor.callproc("PKG_BILLING.ISSUE_INVOICE", [order_id, invoice_id])
        self.connection.commit()
        return invoice_id.getvalue()

    def take_payment(self, invoice_id, amount, method):
        cursor = self.connection.cursor()
        cursor.callproc(
            "PKG_BILLING.APPLY_PAYMENT",
            [invoice_id, amount, method],
        )
        self.connection.commit()
