"""pytest fixtures for the converted PostgreSQL estate.

The suite runs against a local PostgreSQL 16 instance. It rebuilds the schema
once per session from postgres-target/migrations, functions and seed, then runs
each test in its own transaction and rolls back, so tests do not see each
other's writes.

Connection string comes from DATABASE_URL, defaulting to the local demo
instance. No Oracle instance is involved anywhere.
"""

from __future__ import annotations

import os
import sys
from decimal import Decimal
from pathlib import Path

import psycopg
import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import rebuild as rebuild_module

DATABASE_URL = os.environ.get("DATABASE_URL", rebuild_module.DEFAULT_URL)


@pytest.fixture(scope="session", autouse=True)
def built_schema() -> list[Path]:
    """Apply every migration, function and seed file to an empty schema set."""
    applied = rebuild_module.rebuild(DATABASE_URL, quiet=True)
    assert applied, "no SQL files were applied"
    return applied


@pytest.fixture()
def conn():
    with psycopg.connect(DATABASE_URL, autocommit=False) as connection:
        try:
            yield connection
        finally:
            connection.rollback()


@pytest.fixture()
def cur(conn):
    with conn.cursor() as cursor:
        yield cursor


def one(cursor, sql, params=None):
    cursor.execute(sql, params)
    row = cursor.fetchone()
    assert row is not None, f"no row returned by: {sql}"
    return row


def scalar(cursor, sql, params=None):
    return one(cursor, sql, params)[0]


def rows(cursor, sql, params=None):
    cursor.execute(sql, params)
    return cursor.fetchall()


def dec(value) -> Decimal:
    """Expected money value.

    numeric columns come back as decimal.Decimal, so comparisons are exact and
    float tolerance is neither needed nor safe. Decimal equality ignores
    trailing zero differences, so dec('0') == Decimal('0.00').
    """
    return Decimal(str(value))
