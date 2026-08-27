"""Type mapping, constraint and trigger behaviour of the converted schema."""

from __future__ import annotations

import psycopg
import pytest
from conftest import one, rows, scalar

EXPECTED_TYPES = {
    # NUMBER surrogate keys became bigint (information_schema reports the
    # binary precision of bigint, 64 bits, with scale 0)
    ("customers", "customer_id"): ("bigint", 64, 0),
    ("orders", "order_id"): ("bigint", 64, 0),
    # NUMBER without precision stayed numeric with no precision
    ("products", "weight_kg"): ("numeric", None, None),
    ("order_lines", "quantity"): ("numeric", None, None),
    # NUMBER(p,s) carried over exactly
    ("customers", "credit_limit"): ("numeric", 12, 2),
    ("orders", "total_amount"): ("numeric", 14, 2),
    ("order_lines", "discount_rate"): ("numeric", 5, 2),
    # NUMBER(9,0) narrowed to integer
    ("invoice_lines", "quantity"): ("integer", 32, 0),
    # VARCHAR2 CHAR and BYTE both became varchar
    ("customers", "customer_code"): ("character varying", None, None),
    ("customers", "display_name"): ("character varying", None, None),
    # DATE used as a timestamp became timestamp(0) without time zone
    ("customers", "joined_on"): ("timestamp without time zone", None, None),
    ("orders", "ordered_at"): ("timestamp without time zone", None, None),
    # CLOB became text, BLOB and RAW became bytea
    ("customers", "profile_note"): ("text", None, None),
    ("customers", "avatar_blob"): ("bytea", None, None),
    ("customers", "external_ref"): ("bytea", None, None),
}


@pytest.mark.parametrize(("table", "column"), sorted(EXPECTED_TYPES))
def test_type_mapping(cur, table, column):
    expected_type, expected_precision, expected_scale = EXPECTED_TYPES[(table, column)]
    data_type, precision, scale, char_len, dt_precision = one(
        cur,
        """
        SELECT data_type, numeric_precision, numeric_scale,
               character_maximum_length, datetime_precision
        FROM information_schema.columns
        WHERE table_schema = 'retail' AND table_name = %s AND column_name = %s
        """,
        (table, column),
    )
    assert data_type == expected_type
    assert precision == expected_precision
    assert scale == expected_scale
    if data_type == "timestamp without time zone":
        assert dt_precision == 0, "Oracle DATE has second resolution"
    if column == "display_name":
        assert char_len == 160


def test_varchar_char_length_is_characters_not_bytes(cur):
    """VARCHAR2(24 CHAR) became varchar(24): 24 multibyte characters still fit."""
    cur.execute(
        """
        INSERT INTO retail.customers (customer_code, display_name)
        VALUES (%s, 'Multibyte Code Fixture') RETURNING customer_code
        """,
        ("\u00e9" * 24,),
    )
    assert len(cur.fetchone()[0]) == 24


def test_byte_semantics_check_rejects_oversized_multibyte_name(conn, cur):
    """display_name was VARCHAR2(160 BYTE); the octet_length CHECK keeps that limit."""
    with pytest.raises(psycopg.errors.CheckViolation) as excinfo:
        with conn.transaction():
            cur.execute(
                """
                INSERT INTO retail.customers (customer_code, display_name)
                VALUES ('C-BYTES', %s)
                """,
                ("\u00e9" * 100,),  # 100 characters, 200 bytes
            )
    assert "ck_customers_name_bytes" in str(excinfo.value)

    # 80 two byte characters is exactly 160 bytes and is accepted
    cur.execute(
        """
        INSERT INTO retail.customers (customer_code, display_name)
        VALUES ('C-BYTES-OK', %s) RETURNING octet_length(display_name)
        """,
        ("\u00e9" * 80,),
    )
    assert cur.fetchone()[0] == 160


def test_raw16_became_bytea_with_length_check(conn, cur):
    stored = scalar(
        cur, "SELECT external_ref FROM retail.customers WHERE customer_id = 1001"
    )
    assert bytes(stored) == bytes.fromhex("00112233445566778899aabbccddeeff")
    assert len(bytes(stored)) == 16

    with pytest.raises(psycopg.errors.CheckViolation), conn.transaction():
        cur.execute(
            """
                INSERT INTO retail.customers (customer_code, display_name, external_ref)
                VALUES ('C-RAW', 'Raw Length Fixture', %s)
                """,
            (b"\x01\x02\x03",),
        )


def test_clob_and_blob_round_trip(cur):
    note, avatar = one(
        cur,
        "SELECT profile_note, avatar_blob FROM retail.customers WHERE customer_id = 1001",
    )
    assert note.startswith("Fixture root account")
    assert bytes(avatar) == bytes.fromhex("89504e470d0a1a0a")


def test_oracle_empty_string_becomes_null(cur):
    """Oracle stored '' as NULL. The triggers reproduce that for the two columns
    whose CHECK constraints depended on it."""
    channel = scalar(
        cur, "SELECT preferred_channel FROM retail.customers WHERE customer_id = 1008"
    )
    assert channel is None

    flag = scalar(
        cur, "SELECT validated_flag FROM retail.addresses WHERE address_id = 2001"
    )
    assert flag is None

    cur.execute(
        """
        INSERT INTO retail.customers (customer_code, display_name, preferred_channel)
        VALUES ('C-EMPTY-2', 'Second Empty Fixture', '')
        RETURNING preferred_channel
        """
    )
    assert cur.fetchone()[0] is None

    # and on UPDATE, which Oracle also treated as NULL
    cur.execute(
        "UPDATE retail.customers SET preferred_channel = '' WHERE customer_id = 1001"
        " RETURNING preferred_channel"
    )
    assert cur.fetchone()[0] is None


def test_empty_string_elsewhere_is_not_null(cur):
    """Deliberate difference: only the two CHECK-dependent columns are normalised.

    invoice_lines.line_text keeps the PostgreSQL meaning of '', where Oracle
    would have stored NULL. Recorded in CONVERSION-NOTES.md as a loader review
    item.
    """
    text_value = scalar(
        cur, "SELECT line_text FROM retail.invoice_lines WHERE invoice_line_id = 7003"
    )
    assert text_value == ""


def test_check_constraint_still_rejects_empty_string_written_around_trigger(conn, cur):
    """The Oracle CHECK (preferred_channel <> '') could never fire. Here it can,
    which is why the trigger exists. Writing '' directly to the column through a
    path that skips the trigger must still be impossible."""
    with pytest.raises(psycopg.errors.CheckViolation):
        with conn.transaction():
            cur.execute("ALTER TABLE retail.customers DISABLE TRIGGER trg_customers_empty_string")
            cur.execute(
                "INSERT INTO retail.customers (customer_code, display_name, preferred_channel)"
                " VALUES ('C-RAWEMPTY', 'Raw Empty Fixture', '')"
            )


def test_trigger_assigns_key_and_normalises_code(cur):
    customer_id, code, status = one(
        cur,
        """
        INSERT INTO retail.customers (customer_code, display_name, status)
        VALUES ('  c-trigger  ', 'Trigger Fixture', NULL)
        RETURNING customer_id, customer_code, status
        """,
    )
    assert customer_id > 1010, "key came from retail.seq_customers"
    assert code == "C-TRIGGER", "upper(btrim(...)) applied like the Oracle trigger"
    assert status == "A", "NVL(:NEW.status, 'A')"


def test_caller_supplied_key_wins_over_sequence(cur):
    customer_id = scalar(
        cur,
        """
        INSERT INTO retail.customers (customer_id, customer_code, display_name)
        VALUES (7777, 'C-EXPLICIT', 'Explicit Key Fixture')
        RETURNING customer_id
        """,
    )
    assert customer_id == 7777


def test_sequences_start_values_and_alignment(cur):
    seq_rows = rows(
        cur,
        """
        SELECT c.relname, s.seqstart, s.seqincrement, s.seqcache
        FROM pg_class c
        JOIN pg_sequence s ON s.seqrelid = c.oid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'retail'
        ORDER BY c.relname
        """,
    )
    starts = {name: (start, increment, cache) for name, start, increment, cache in seq_rows}
    assert len(starts) == 9
    assert starts["seq_customers"] == (1001, 1, 1), "Oracle NOCACHE maps to CACHE 1"
    assert starts["seq_orders"] == (5001, 1, 1)

    # aligned past the seeded keys by S003
    assert scalar(cur, "SELECT nextval('retail.seq_orders')") > 5012


def test_derived_totals_trigger_matches_source_behaviour(cur):
    """trg_order_lines_ai sets subtotal and total from the line sum. The tax
    part is added afterwards by refresh_order_total, exactly as in Oracle."""
    cur.execute(
        """
        INSERT INTO retail.order_lines (order_id, line_number, product_id, quantity,
                                        unit_price, discount_rate, extended_amount)
        VALUES (5003, 1, 3001, 3, 10.00, 0, 30.00)
        """
    )
    subtotal, total, tax = one(
        cur,
        "SELECT subtotal_amount, total_amount, tax_amount FROM retail.orders WHERE order_id = 5003",
    )
    assert (subtotal, total, tax) == (30, 30, 0)


def test_payment_trigger_decode_translation(cur):
    """DECODE(invoice_status, 'VOID', 'VOID', 'PARTIAL') became a CASE."""
    cur.execute(
        "INSERT INTO retail.payments (invoice_id, amount_paid) VALUES (6002, 1.00)"
    )
    assert scalar(cur, "SELECT invoice_status FROM retail.invoices WHERE invoice_id = 6002") == "PARTIAL"

    cur.execute(
        "INSERT INTO retail.payments (invoice_id, amount_paid) VALUES (6003, 1.00)"
    )
    assert scalar(cur, "SELECT invoice_status FROM retail.invoices WHERE invoice_id = 6003") == "VOID"


def test_audit_trigger_defaults(cur):
    audit_id, event_time = one(
        cur,
        """
        INSERT INTO retail.audit_log (entity_name, entity_id, action_code, event_time)
        VALUES ('ORDER', 5001, 'TESTED', NULL)
        RETURNING audit_id, event_time
        """,
    )
    assert audit_id > 9001
    assert event_time is not None


def test_boundary_dates_survived(cur):
    joined, contacted = one(
        cur,
        "SELECT joined_on, last_contacted_on FROM retail.customers WHERE customer_id = 1009",
    )
    assert str(joined) == "1900-01-01 00:00:00"
    assert str(contacted) == "2000-02-29 23:59:59", "leap day kept"

    assert str(
        scalar(cur, "SELECT ordered_at FROM retail.orders WHERE order_id = 5011")
    ) == "2999-12-31 23:59:59"


def test_object_counts(cur):
    counts = {}
    counts["tables"] = scalar(
        cur,
        "SELECT count(*) FROM information_schema.tables"
        " WHERE table_schema = 'retail' AND table_type = 'BASE TABLE'",
    )
    counts["views"] = scalar(
        cur, "SELECT count(*) FROM information_schema.views WHERE table_schema = 'retail'"
    )
    counts["matviews"] = scalar(
        cur, "SELECT count(*) FROM pg_matviews WHERE schemaname = 'retail'"
    )
    counts["sequences"] = scalar(
        cur, "SELECT count(*) FROM information_schema.sequences WHERE sequence_schema = 'retail'"
    )
    counts["triggers"] = scalar(
        cur,
        "SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid"
        " JOIN pg_namespace n ON n.oid = c.relnamespace"
        " WHERE n.nspname = 'retail' AND NOT t.tgisinternal",
    )
    counts["functions"] = scalar(
        cur,
        "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace"
        " WHERE n.nspname IN ('pkg_order_mgmt', 'pkg_billing', 'pkg_customer_hier')",
    )
    # 10 source tables plus the GTT template
    assert counts["tables"] == 11
    assert counts["views"] == 5, "3 source views, 1 synonym replacement, 1 deduped variant"
    assert counts["matviews"] == 1
    assert counts["sequences"] == 9
    assert counts["triggers"] == 10
    # 14 converted package routines plus 3 package state accessors in
    # pkg_order_mgmt (g_call_count, g_last_order_id, reset_package_state),
    # 1 in pkg_billing (g_run_label) and the dblink variant of the autonomous
    # logger
    assert counts["functions"] == 19
