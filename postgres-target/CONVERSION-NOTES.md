# Oracle to PostgreSQL 16 conversion notes

Source: `oracle-legacy-estate/` (synthetic Oracle 19c style estate, no real data).
Target: `postgres-target/`, executed against PostgreSQL 16.15.

Every statement in this directory has been run. The test run that backs these
notes is in `tests/EVIDENCE.md`.

Legend for the verdict column:

- **Equivalent**: same observable behaviour, verified by a test.
- **Deliberately different**: behaviour changed on purpose, reason given. A test
  pins the new behaviour so the difference cannot drift unnoticed.
- **Human decision**: the conversion picked a default that works, but the
  correct answer depends on business or infrastructure context. Listed again in
  the sign off section at the end.

## 1. Type mapping

| Oracle type | Used for | PostgreSQL type | Verdict | Reason |
| --- | --- | --- | --- | --- |
| `NUMBER` (no precision) on keys | `customer_id`, `order_id`, all surrogate keys | `bigint` | Deliberately different | Oracle `NUMBER` holds 38 digits. Keys here come from sequences starting at four digits, so `bigint` is right and gives fixed width comparisons and smaller indexes. `numeric` would have preserved the theoretical range at real cost. If any key is ever expected to exceed 9.2e18, this is wrong; nothing in the estate suggests it. |
| `NUMBER` (no precision) on quantities | `order_lines.quantity`, `gtt_order_totals.line_count` | `numeric` | Equivalent | Quantity is genuinely fractional in the fixture (order 5005 has quantity 2.5), and unconstrained `numeric` keeps arbitrary scale, matching Oracle. |
| `NUMBER(p,s)` | money and rates | `numeric(p,s)` | Equivalent | Direct match, same rounding via `round(v, s)`. |
| `NUMBER(9,0)` | small integer counters | `integer` | Deliberately different | 9 digits fits in `integer`. Cheaper and it makes the intent (integral) explicit in the type. |
| `VARCHAR2(n CHAR)` | most text columns | `varchar(n)` | Equivalent | PostgreSQL `varchar(n)` counts characters, which is what `CHAR` semantics mean. |
| `VARCHAR2(n BYTE)` | `customers.display_name`, `products.description` | `varchar(n)` plus a check constraint on `octet_length` | Deliberately different | PostgreSQL has no byte length limit for character types. The check constraint reproduces the limit that mattered: a string of multibyte characters that Oracle rejected is still rejected. The character count limit is now looser than Oracle's byte limit, which is the safe direction. |
| `DATE` used as a timestamp | `ordered_at`, `issued_on`, `event_time` | `timestamp(0) without time zone` | Equivalent | Oracle `DATE` carries a time to the second and no zone. `timestamp(0)` is exactly that. Using `date` would have silently truncated the time; using `timestamptz` would have invented a zone the source never had. |
| `CLOB` | `profile_note`, `delivery_note`, `audit_log.payload` | `text` | Equivalent | No length limit, no separate LOB handle. Removes all `DBMS_LOB` code (see 3.14). |
| `BLOB` | `customers.avatar_blob` | `bytea` | Deliberately different | `bytea` is read and written whole, with no streaming API and a practical 1 GB limit. Fine for the sizes here. If the real estate streams large binaries, PostgreSQL large objects (`lo`) are the alternative and they change the application code, so this one is worth confirming against real sizes. |
| `RAW(16)` | `customers.external_ref` | `bytea` plus `octet_length = 16` check | Equivalent | The fixed width is the point of `RAW(16)`, and the check keeps it. `uuid` was considered and rejected because nothing proves every value is a UUID. |

## 2. Schema objects

| Oracle object | PostgreSQL treatment | Verdict | Notes |
| --- | --- | --- | --- |
| 11 tables, all constraints | Same tables in schema `retail` (`V002`) | Equivalent | Check, unique, not null and foreign key constraints carried over one for one. |
| 9 sequences | 9 sequences in `retail` (`V003`) | Equivalent | Kept as sequences rather than converted to identity columns, because the triggers and the packages call them by name and the application relies on the numbering. `CACHE 1` preserves the source's gap free intent. |
| Trigger based key assignment (`BEFORE INSERT ... :NEW.id := seq.NEXTVAL`) | `BEFORE INSERT` trigger functions calling `nextval` (`V007`) | Equivalent | Identity columns would have been more idiomatic but would break the callers that insert an explicit id, which the seed data and `pkg_billing.issue_invoice` both do. |
| Regular indexes | Same indexes (`V004`) | Equivalent | |
| Bitmap index `bix_orders_status` | B-tree index on `order_status` plus partial index `ix_orders_status_open` on the hot statuses | Deliberately different | PostgreSQL has no persistent bitmap index; it builds bitmaps at run time from b-tree scans. The partial index is the closest thing to the bitmap's advantage on low cardinality columns. Size and plans will differ from Oracle. |
| Index organized table `order_lines` | Ordinary heap table, `CLUSTER ON pk_order_lines` (`V006`) | Deliberately different | PostgreSQL has no IOT. `CLUSTER` orders the heap once but does not maintain that order, so range scans on the primary key degrade as rows are inserted. A periodic `CLUSTER` (or accepting the index only scan) is a DBA decision. |
| Global temporary table `gtt_order_totals` | Permanent empty template `gtt_order_totals_template` plus `retail.ensure_gtt_order_totals()` creating a session `TEMP TABLE ... ON COMMIT DELETE ROWS` (`V006`) | Deliberately different | Oracle GTTs are permanent definitions with session private data. PostgreSQL temp tables are created per session, so the definition lives in the template and the helper materialises it on first use. `ON COMMIT DELETE ROWS` matches the Oracle default. The visible difference: the table does not exist until the helper runs, so a plain `SELECT` before any call fails instead of returning zero rows. |
| Synonym `current_orders` | Updatable view `retail.current_orders` (`V006`) | Equivalent | PostgreSQL has no synonyms. A simple `SELECT *` view is automatically updatable, so inserts and updates through the name still work. |
| Materialized view `mv_customer_order_rollup` | Materialized view plus `retail.refresh_customer_order_rollup()` (`V006`) | Deliberately different | Oracle's `REFRESH ON COMMIT` has no PostgreSQL equivalent. The view goes stale until refreshed. `REFRESH MATERIALIZED VIEW CONCURRENTLY` is possible because a unique index exists on `customer_id`. Who calls the refresh, and how often, is a human decision. |
| 3 reporting views | Same views (`V005`), `(+)` rewritten as `LEFT JOIN`, `NVL` as `COALESCE` | Equivalent | |
| `v_customer_balance` payment fan out | Converted faithfully, bug included, plus a corrected `v_customer_balance_deduped` alongside | Human decision | The source view joins invoices to payments and sums invoice totals, so an invoice with two payments counts its total twice. Invoice 6001 in the fixture has two payments and reproduces it. Both views are tested. Which one production should use is a business call, not a conversion call. |
| 10 triggers (key assignment, normalisation, derived totals, payment status, audit defaults) | Trigger functions plus triggers (`V007`) | Equivalent | PL/pgSQL trigger functions return `NEW`; the `:NEW.x := y` assignments carry over unchanged in meaning. |

## 3. PL/SQL constructs

| # | Oracle construct | Where | PostgreSQL treatment | Verdict |
| --- | --- | --- | --- | --- |
| 3.1 | Package with spec and body | all three packages | Schema per package, function per member. `OUT` parameters become return values; `SYS_REFCURSOR` becomes `RETURNS TABLE` | Deliberately different |
| 3.2 | Package level variables (`g_call_count`, `g_last_order_id`, `g_run_label`) | `pkg_order_mgmt`, `pkg_billing` | Session GUCs in a matching namespace, wrapped by accessor functions | Human decision |
| 3.3 | `PRAGMA AUTONOMOUS_TRANSACTION` with its own `COMMIT` | `pkg_billing.write_billing_log` | Default: plain insert in the caller's transaction. Optional `write_billing_log_autonomous` uses `dblink` when installed and degrades to the default when it is not | Human decision |
| 3.4 | `SAVEPOINT` plus `ROLLBACK TO` in an exception handler | `pkg_order_mgmt.create_order`, `load_order_totals` | `BEGIN ... EXCEPTION` block. PL/pgSQL opens an implicit subtransaction for any block with a handler and rolls it back before running the handler. Explicit `SAVEPOINT` is not permitted inside a function | Equivalent |
| 3.5 | `ROWNUM` pagination through nested inline views | `pkg_order_mgmt.list_customer_orders` | `LIMIT` and `OFFSET`, with `order_id` added as a tiebreaker | Deliberately different (stable page boundaries the original did not guarantee) |
| 3.6 | `CONNECT BY PRIOR`, `LEVEL`, `ORDER SIBLINGS BY` | `pkg_customer_hier.print_tree`, `list_ancestors`, `descendant_count` | Recursive CTEs. `LEVEL` becomes a depth column, `ORDER SIBLINGS BY` becomes an accumulated sort path array ordered at the end | Equivalent |
| 3.7 | `MINUS` | `pkg_customer_hier.find_unordered_customers` | `EXCEPT` | Equivalent |
| 3.8 | `SELECT ... FROM DUAL` | three call sites | Removed. PostgreSQL evaluates a `SELECT` of expressions with no table, and assignment does not need a query at all | Equivalent |
| 3.9 | `SYSDATE` | throughout | `retail.sysdate()` returning `clock_timestamp()::timestamp(0)` | Equivalent. `clock_timestamp()` was chosen over `now()` because Oracle `SYSDATE` advances within a transaction while `now()` is fixed at transaction start |
| 3.10 | `(+)` outer joins | `summarize_order`, views, `raw_queries.sql` | Explicit `LEFT JOIN` | Equivalent |
| 3.11 | Optimizer hints (`/*+ FIRST_ROWS(25) INDEX(...) */`) | `list_customer_orders`, `raw_queries.sql` | Dropped. Core PostgreSQL has no hint syntax; the named indexes still exist | Deliberately different, plans need review under real volumes |
| 3.12 | `BULK COLLECT` plus `FORALL` | `load_order_totals`, `rebuild_invoice_totals` | Set based `INSERT ... SELECT` and a single `UPDATE`. PL/pgSQL has no collection bulk binding and does not need one | Deliberately different (same result, fewer statements) |
| 3.13 | Reverse `FOR` loop | `summarize_order` | `FOR i IN REVERSE high..low`. Note the operand order is the opposite of PL/SQL | Equivalent |
| 3.14 | `DBMS_LOB.CREATETEMPORARY`, `WRITEAPPEND`, `ISTEMPORARY`, `FREETEMPORARY` | `issue_invoice` | One `text` assignment. No handles, so no allocation or cleanup path | Equivalent |
| 3.15 | `DBMS_OUTPUT.PUT_LINE` | all three packages | `RAISE NOTICE`, and where the output was the only result, the value is also returned so it can be asserted | Deliberately different |
| 3.16 | Dynamic SQL by string concatenation of identifiers | `create_order`, `rebuild_invoice_totals` | `format()` with `%I` for identifiers and `USING` for values, so the injection path in the original is gone | Deliberately different (safer, same behaviour) |
| 3.17 | `RAISE_APPLICATION_ERROR(-20901 ...)` | several | `RAISE EXCEPTION ... USING ERRCODE = 'OR901'`. Five digit Oracle codes map to the five character SQLSTATE `OR9xx` |  Deliberately different (callers matching on `-20901` must be updated) |
| 3.18 | `DUP_VAL_ON_INDEX`, `NO_DATA_FOUND`, `WHEN OTHERS` | several | `unique_violation`, `no_data_found` (via `INTO STRICT`), `WHEN OTHERS` | Equivalent |
| 3.19 | `SELECT ... FOR UPDATE` | `apply_payment` | Same syntax, same row lock | Equivalent |
| 3.20 | `DECODE`, `NVL`, `NVL2`, `GREATEST` | throughout | `CASE`, `COALESCE`, `COALESCE`, `GREATEST` | Equivalent |
| 3.21 | `seq.NEXTVAL` then `seq.CURRVAL` | `issue_invoice` | One `nextval` into a variable, reused | Equivalent, and no longer depends on session sequence state |
| 3.22 | Paid in full comparison that ignores `tax_total` | `apply_payment` | Preserved as is | Human decision. This looks like a source defect: an invoice is marked `PAID` when `invoice_total` is covered even though tax is still outstanding. It is converted faithfully and pinned by a test, so fixing it is a separate, visible change |

## 4. Semantics that could not be preserved

1. **Autonomous transaction logging** (3.3). With the default in transaction
   insert, a caller rollback removes the audit row. Oracle kept it. Three
   mitigations exist and all cost something: `dblink` (extension plus
   credentials), `pg_background` (out of core extension), or moving logging to
   the application after commit.
2. **Package state across a rollback** (3.2). A GUC set with `set_config(..., false)`
   is transactional, so a rollback restores the previous value. Oracle package
   variables survive. A test asserts the new behaviour explicitly.
3. **Empty string is not NULL.** Oracle treats `''` as `NULL`; PostgreSQL keeps
   it as a zero length string. `retail.oracle_empty_to_null()` and normalisation
   triggers apply the Oracle rule on the columns where the estate clearly relies
   on it. Anywhere else, a value that used to read as `NULL` now reads as `''`,
   and `IS NULL` filters change answers. Migrated data must be scrubbed. This is
   the single highest risk item in the conversion.
4. **`ORDER BY` and default collation.** Oracle sorted with its own NLS rules.
   PostgreSQL sorts with the database collation. Mixed case and punctuation heavy
   values can order differently. Nothing in the fixture depends on it, so no
   `COLLATE` clauses were added.
5. **IOT clustering** (section 2). Order is maintained continuously in Oracle,
   one time in PostgreSQL.
6. **Materialized view freshness** (section 2). `ON COMMIT` refresh is gone.
7. **Optimizer hints** (3.11). Plan stability is now the planner's business plus
   statistics.

## 5. What a DBA must sign off

1. `bigint` for surrogate keys, confirming no key exceeds `bigint` range.
2. The `octet_length` check constraints as the replacement for `VARCHAR2 BYTE`
   limits, including the server encoding those limits assume.
3. `bytea` for `BLOB`, after checking real object sizes against the whole value
   read and write model.
4. The autonomous logging decision: accept in transaction logging, or approve
   `dblink` with a connection string and a security review.
5. Whether any caller reads package state after a failed transaction (3.2).
6. `CLUSTER` policy for `retail.order_lines`, or accepting index only scans.
7. Refresh policy and owner for `mv_customer_order_rollup`, including whether
   `CONCURRENTLY` is required.
8. Bitmap index replacement: whether the partial index set matches real query
   patterns, once statistics from production volumes exist.
9. Which customer balance view is correct (`v_customer_balance` as converted, or
   `v_customer_balance_deduped`).
10. The `apply_payment` tax comparison (3.22): keep the source behaviour or fix
    it.
11. Error code mapping `-20901` to `OR901` and the application changes it
    implies (3.17).
12. Data scrub plan for empty string versus NULL before cutover (section 4.3).
13. Sequence start values after a real data load. `seed/S003` aligns them for
    the fixture; production needs the same step sized to the loaded data.

## 6. Application tier

`oracle-legacy-estate/app/dao.py` and `order_worker.py` are unchanged. The
converted versions sit beside them:

| Oracle | PostgreSQL | Change |
| --- | --- | --- |
| `dao.py` | `dao_postgres.py` | `oracledb.connect` to `psycopg.connect`, `cursor.callproc` with `cursor.var` OUT parameters to `SELECT schema.function(...)`, ref cursor to `SELECT * FROM function(...)`, `:name` binds to `%(name)s` |
| `order_worker.py` | `order_worker_postgres.py` | Import swap. The call sequence is identical; the payment step now reads a returned status instead of `DBMS_OUTPUT` |
| `raw_queries.sql` | `raw_queries_postgres.sql` | Hints dropped, `(+)` to `LEFT JOIN`, `ROWNUM` to `LIMIT`, `CONNECT BY` to the converted function, `:end_date + 1` to `+ interval '1 day'`, `DUAL` removed |

One trap worth naming for the wider application port: psycopg infers PostgreSQL
types from Python types, so a small `int` arrives as `smallint` and a `float` as
`double precision`, and function resolution then fails to find the `bigint` and
`numeric` signatures. Every argument in the converted DAO is cast explicitly.
PL/SQL `NUMBER` accepted anything numeric, so nothing in the Oracle code hinted
at this.

## 7. Running it

```
python3 postgres-target/scripts/rebuild.py            # migrations, functions, seed
python3 -m pytest postgres-target/tests -q            # the suite
```

Both read `DATABASE_URL` and fall back to the local demo instance. See
`tests/EVIDENCE.md` for the actual run.
