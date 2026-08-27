# postgres-target

PostgreSQL 16 conversion of the synthetic Oracle estate in
`../oracle-legacy-estate`. Everything here has been executed against
PostgreSQL 16.15. Synthetic fixture data only, no credentials.

```
migrations/   Flyway style versioned DDL, V001 to V007
functions/    the three PL/SQL packages, one schema per package
seed/         deterministic fixture rows, S001 to S003
scripts/      rebuild.py, applies migrations, functions and seed in order
tests/        pytest plus psycopg suite, and EVIDENCE.md with the real run
CONVERSION-NOTES.md   construct by construct treatment and DBA sign off list
```

## Local database

Any PostgreSQL 16 works. The one used for the recorded run:

```
docker run -d --name pgdemo -e POSTGRES_USER=demo -e POSTGRES_PASSWORD=demo \
  -e POSTGRES_DB=oracle_migration_demo -p 55432:5432 postgres:16
```

## Apply and test

```
python3 -m venv .venv-pg
.venv-pg/bin/pip install 'psycopg[binary]' pytest

.venv-pg/bin/python postgres-target/scripts/rebuild.py
.venv-pg/bin/python -m pytest postgres-target/tests -q
```

Both scripts read `DATABASE_URL` and default to
`postgresql://demo:demo@127.0.0.1:55432/oracle_migration_demo`. The test suite
rebuilds the schema once per session, so `rebuild.py` is only needed when you
want to inspect the database by hand.

## Migration order

| File | Contents |
| --- | --- |
| `V001__schemas_and_helpers.sql` | schemas `retail`, `pkg_order_mgmt`, `pkg_billing`, `pkg_customer_hier`, plus `retail.sysdate()` and the empty string helper |
| `V002__tables.sql` | 11 tables, constraints, byte length checks |
| `V003__sequences.sql` | 9 sequences |
| `V004__indexes.sql` | indexes, including the bitmap index replacement |
| `V005__views.sql` | reporting views |
| `V006__oracle_only_objects.sql` | IOT, synonym, materialized view and global temporary table equivalents |
| `V007__triggers.sql` | trigger functions and triggers |

Flyway is not run here, the file names follow its convention so the same set
can be handed to Flyway or Liquibase without renaming. `rebuild.py` applies them
in lexical order and drops the converted schemas first, so it is destructive by
design and only ever points at a local demo database.
