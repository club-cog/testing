#!/usr/bin/env python3
"""Rebuild the converted PostgreSQL schema from scratch.

Applies, in order: migrations/V*.sql, functions/*.sql, seed/S*.sql.

Flyway is the intended tool in a real pipeline; this script exists so the demo
runs with nothing installed but psycopg. The file naming matches Flyway
conventions (V for versioned migrations), and the function files are the
repeatable part, equivalent to Flyway R__ migrations.

Usage:
    python3 postgres-target/scripts/rebuild.py
    DATABASE_URL=postgresql://user:pw@host:port/db python3 .../rebuild.py
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import psycopg

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_URL = "postgresql://demo:demo@127.0.0.1:55432/oracle_migration_demo"
SCHEMAS = ("retail", "pkg_order_mgmt", "pkg_billing", "pkg_customer_hier")


def sql_files() -> list[Path]:
    files: list[Path] = []
    files.extend(sorted((ROOT / "migrations").glob("V*.sql")))
    files.extend(sorted((ROOT / "functions").glob("*.sql")))
    files.extend(sorted((ROOT / "seed").glob("S*.sql")))
    return files


def rebuild(url: str, quiet: bool = False) -> list[Path]:
    applied: list[Path] = []
    with psycopg.connect(url, autocommit=True) as conn:
        for schema in SCHEMAS:
            conn.execute(f"DROP SCHEMA IF EXISTS {schema} CASCADE")
        # Session temp tables from an earlier run would confuse the GTT helper.
        conn.execute("DISCARD TEMP")

    for path in sql_files():
        # One connection per file so a failure names the file that failed.
        with psycopg.connect(url, autocommit=False) as conn:
            conn.execute(path.read_text())
            conn.commit()
        applied.append(path)
        if not quiet:
            print(f"applied {path.relative_to(ROOT.parent)}")
    return applied


def main() -> int:
    url = os.environ.get("DATABASE_URL", DEFAULT_URL)
    applied = rebuild(url)
    print(f"rebuild complete: {len(applied)} files applied to {url.rsplit('/', 1)[-1]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
