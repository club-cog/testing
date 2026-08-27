# Oracle characterization tests

These are the tests that pin down what the Oracle estate in
`oracle-legacy-estate/` does today, written before any conversion work starts.
The point is to make the current behaviour explicit and machine checkable, so the
same expectations can be replayed against the PostgreSQL target and any
difference shows up as a failing assertion instead of a support ticket.

## Status: authored, not executed

No Oracle instance was available in the session that produced these files, and no
attempt was made to install or reach one. Nothing in this directory has been
executed against any database, Oracle or PostgreSQL.

Every expected value in `expectations/expected-behaviour.md` was derived by
reading the source under `packages/`, `ddl/`, `triggers/` and `views/`. Treat the
whole suite as a set of predictions about Oracle that still needs its first run.
The first execution against the real Oracle schema is expected to correct some
expectations, and correcting them is the point: a mismatch found there is a
misreading of the code, and it is much cheaper to fix before conversion than
after.

## Layout

```
tests/
  oracle/
    ut_estate_fixture.pks/.pkb      shared support, no tests
    ut_pkg_order_mgmt.pks/.pkb      33 tests
    ut_pkg_billing.pks/.pkb         23 tests
    ut_pkg_customer_hier.pks/.pkb   17 tests
  fixtures/
    000_reset_fixture_data.sql      removes fixture and test generated rows
    010_customers.sql               12 customers, five level hierarchy
    020_addresses.sql
    030_products_price_tiers.sql
    040_orders_lines.sql
    050_invoices_payments.sql
    060_align_sequences.sql         restarts sequences at 100001
  expectations/
    expected-behaviour.md           the signoff document
```

## Prerequisites

- Oracle 19c or compatible, with a schema that can create packages and sequences.
- utPLSQL v3 (3.1.10 or newer) installed in the database. It is not part of
  Oracle, it has to be installed separately: https://github.com/utPLSQL/utPLSQL
- A client that can run scripts and show DBMS_OUTPUT. The commands below use
  SQL\*Plus; SQLcl works the same way.

Install utPLSQL into its own schema and grant the test schema access to it, per
the project's own instructions. A minimal install looks like this, run as a user
with DBA privileges:

```sql
-- from the unpacked utPLSQL source directory
@source/install_headless.sql UT3 ut3_password USERS
```

Then grant the estate schema the right to run it:

```sql
GRANT ut3.ut_runner_role TO estate_owner;
```

## Order of setup

Run everything as the schema that owns the estate objects. The order matters:
tables, then sequences and indexes, then derived objects, then triggers, then
views, then the fixtures, then the test packages.

```sh
sqlplus estate_owner/@//host:1521/service <<'SQL'
@oracle-legacy-estate/ddl/001_tables.sql
@oracle-legacy-estate/ddl/002_sequences_indexes.sql
@oracle-legacy-estate/ddl/003_derived_objects.sql
@oracle-legacy-estate/triggers/001_key_assignment.sql
@oracle-legacy-estate/triggers/002_derived_values.sql
@oracle-legacy-estate/views/001_reporting_views.sql
@oracle-legacy-estate/packages/pkg_order_mgmt.pks
@oracle-legacy-estate/packages/pkg_order_mgmt.pkb
@oracle-legacy-estate/packages/pkg_billing.pks
@oracle-legacy-estate/packages/pkg_billing.pkb
@oracle-legacy-estate/packages/pkg_customer_hier.pks
@oracle-legacy-estate/packages/pkg_customer_hier.pkb
SHOW ERRORS
SQL
```

## Loading the fixtures

The fixture scripts are plain `INSERT` statements with explicit primary keys, and
each file ends with `COMMIT`. Load them in file name order, and load the reset
script first if the schema has been used before.

```sh
sqlplus estate_owner/@//host:1521/service <<'SQL'
@oracle-legacy-estate/tests/fixtures/000_reset_fixture_data.sql
@oracle-legacy-estate/tests/fixtures/010_customers.sql
@oracle-legacy-estate/tests/fixtures/020_addresses.sql
@oracle-legacy-estate/tests/fixtures/030_products_price_tiers.sql
@oracle-legacy-estate/tests/fixtures/040_orders_lines.sql
@oracle-legacy-estate/tests/fixtures/050_invoices_payments.sql
@oracle-legacy-estate/tests/fixtures/060_align_sequences.sql
SQL
```

Two things to know about the fixture data:

- All fixture keys sit between 90000 and 99999, and the sequences are restarted
  at 100001. Anything at or above 100000 was created by a test run, which is how
  the cleanup script and the audit purge tell the two apart.
- Two order rows use `SYSDATE` arithmetic on purpose, because
  `pkg_customer_hier.find_unordered_customers` filters on `SYSDATE - 90` and a
  fixed literal would drift out of the window over time. Everything else uses
  fixed literals so that ordering and pagination stay deterministic.

## Compiling and running the suite

```sh
sqlplus estate_owner/@//host:1521/service <<'SQL'
@oracle-legacy-estate/tests/oracle/ut_estate_fixture.pks
@oracle-legacy-estate/tests/oracle/ut_estate_fixture.pkb
@oracle-legacy-estate/tests/oracle/ut_pkg_order_mgmt.pks
@oracle-legacy-estate/tests/oracle/ut_pkg_order_mgmt.pkb
@oracle-legacy-estate/tests/oracle/ut_pkg_billing.pks
@oracle-legacy-estate/tests/oracle/ut_pkg_billing.pkb
@oracle-legacy-estate/tests/oracle/ut_pkg_customer_hier.pks
@oracle-legacy-estate/tests/oracle/ut_pkg_customer_hier.pkb
SHOW ERRORS
SQL
```

Run everything:

```sh
sqlplus -s estate_owner/@//host:1521/service <<'SQL'
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET PAGESIZE 0
SET FEEDBACK OFF
BEGIN
    ut.run('estate.oracle');
END;
/
SQL
```

Run one suite or one test:

```sql
BEGIN ut.run('estate_owner.ut_pkg_billing'); END;
/
BEGIN ut.run('estate_owner.ut_pkg_billing.payment_on_void_invoice'); END;
/
```

## Capturing the output

For a JUnit file that CI can read:

```sh
sqlplus -s estate_owner/@//host:1521/service <<'SQL' > ut-results.xml
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 32767 PAGESIZE 0 FEEDBACK OFF TRIMSPOOL ON HEADING OFF
BEGIN
    ut.run('estate.oracle', ut_junit_reporter());
END;
/
SQL
```

The utPLSQL CLI produces the same thing without the SQL\*Plus formatting dance,
if it is available on the runner:

```sh
utplsql run estate_owner/password@//host:1521/service \
    -p=estate.oracle \
    -f=ut_junit_reporter -o=ut-results.xml \
    -f=ut_documentation_reporter -o=ut-results.txt -s
```

`SET SERVEROUTPUT ON` is not optional. Three procedures in this estate report
their result only through `DBMS_OUTPUT` (`pkg_order_mgmt.summarize_order`,
`pkg_customer_hier.print_tree` and the label reporting in
`pkg_billing.rebuild_invoice_totals`), and the tests read the buffer back through
`ut_estate_fixture.captured_output`.

## Transactions, autonomous commits and the temp table

Three behaviours of this estate make test isolation more than a formality, and
the suite handles each one explicitly rather than hiding it:

1. Most tests run under `--%rollback(auto)`, so utPLSQL wraps each test in a
   savepoint and rolls it back. The fixture rows survive untouched.
2. `pkg_billing.write_billing_log` is declared with
   `PRAGMA AUTONOMOUS_TRANSACTION` and commits its own work, so audit rows are
   **not** rolled back with the test that produced them.
   `ut_pkg_billing.test_teardown` deletes them autonomously after every test, and
   two tests that need a real `COMMIT` boundary are marked `--%rollback(manual)`
   and clean up after themselves. If a run is interrupted, clear the leftovers
   with:

   ```sql
   BEGIN ut_estate_fixture.purge_generated_audit_rows; END;
   /
   ```

3. `gtt_order_totals` is a global temporary table with `ON COMMIT DELETE ROWS`.
   The `load_order_totals` tests never commit, so the rows stay visible for the
   duration of the test and disappear on the savepoint rollback.

Package state is a fourth case, and it is deliberately not isolated.
`pkg_order_mgmt.g_last_order_id` and the label inside `pkg_billing` are session
scoped and survive a rollback. Several tests assert exactly that, which means the
suite must be run in a session where nothing else has already called those
packages.

## Resetting the schema

`fixtures/000_reset_fixture_data.sql` deletes the fixture rows and everything a
test run generated (keys at or above 100000), in dependency order. Run it before
reloading the fixtures, not after a run, so that a failed run can still be
inspected.

## Replaying the same expectations against PostgreSQL

The fixture files are written to port with minimal edits: explicit keys, no
Oracle only functions except `SYSDATE`, one `INSERT` per statement. The expected
edits are `SYSDATE` to `LOCALTIMESTAMP` and `TO_DATE(...)` to a timestamp
literal.

The test packages themselves do not port mechanically, and pretending otherwise
would be dishonest: utPLSQL has no PostgreSQL equivalent, so the target side
needs pgTAP or a plain SQL harness. What ports is
`expectations/expected-behaviour.md`. Every row in it is a concrete input and a
concrete expected output, and the table at the end of that file lists the cases
where the PostgreSQL answer is legitimately different and the migration has to
make a decision. Those are the rows to settle with the customer DBA before the
conversion starts, not after.
