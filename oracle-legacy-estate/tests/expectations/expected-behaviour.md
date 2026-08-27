# Expected behaviour of the Oracle estate before conversion

This is the signoff document for the characterization suite in
`oracle-legacy-estate/tests/oracle/`. It lists every test, the exact result the
test asserts, and why that result is what Oracle produces. The same expectations
are meant to be replayed against the converted PostgreSQL schema, so the last
section records the places where PostgreSQL will legitimately give a different
answer and what the migration has to decide.

## Provenance of these expectations, read this first

No Oracle instance was available in the session that wrote these files. Nothing
here has been executed. Every expected value was derived by reading the source
in `packages/`, `ddl/`, `triggers/` and `views/`, and every one of them is
therefore a claim about the code, not an observation of a run.

- Source derived: all 73 expectations below.
- Executed against Oracle: none.
- Executed against PostgreSQL: none.

The intended order of work is: run this suite against the Oracle source schema
first, correct any expectation the real database disagrees with, get the
corrected file signed off, and only then convert. An expectation that Oracle
contradicts is a defect in this document, not in Oracle.

A handful of cases are marked "environment dependent" in the reason column. Those
depend on NLS settings, the session clock or the sequence high water mark, and
the tests deliberately assert a pattern or a relationship instead of a literal.

## Test counts

| Test package | Source package under test | Tests |
| --- | --- | --- |
| `ut_pkg_order_mgmt` | `pkg_order_mgmt` | 33 |
| `ut_pkg_billing` | `pkg_billing` | 23 |
| `ut_pkg_customer_hier` | `pkg_customer_hier` | 17 |
| Total | | 73 |

`ut_estate_fixture` is shared support code (fixture key constants, DBMS_OUTPUT
capture, autonomous audit cleanup) and holds no tests.

## Fixture data the expectations depend on

Loaded by `tests/fixtures/*.sql` in file name order. Customers 90001 to 90012,
addresses 91001 to 91005, products 92001 to 92005, price tiers 92501 to 92503,
orders 93001 to 93010, invoices 94001 to 94003, invoice lines 94501 to 94503,
payments 95001 to 95002. Ids 99901, 99902 and 99903 are deliberately absent and
stand for "not found". Sequences are restarted at 100001 by
`fixtures/060_align_sequences.sql`, so any key at or above 100000 was generated
by a test rather than seeded.

The hierarchy is five levels deep:

```
90001 ROOT-CO
  90002 REGION-NORTH
    90004 BRANCH-N1
      90006 DEPT-N1A      status H
        90007 TEAM-N1A1
    90005 BRANCH-N2
  90003 REGION-SOUTH
```

## pkg_order_mgmt

### create_order

| Test | Expected result | Reason |
| --- | --- | --- |
| `create_null_requester_is_open` | New order id is not null, `order_status` = `OPEN`, `requested_by` = `BATCH`, `total_amount` = 0 | `NVL(p_requested_by, 'BATCH')` supplies the requester and the `DECODE` on the same argument returns `OPEN` for NULL. The zero total comes from the `NVL` in `trg_orders_bi`, not from the package. |
| `create_named_requester_is_held` | `order_status` = `HELD`, `requested_by` = `ANNA-FIXTURE` | The `DECODE` maps anything that is neither NULL nor `BATCH` to `HELD`. |
| `create_literal_batch_is_open` | `order_status` = `OPEN` | `BATCH` is an explicit `DECODE` branch, so a caller passing the literal is indistinguishable from a caller passing nothing. |
| `create_empty_requester_is_batch` | `order_status` = `OPEN`, `requested_by` = `BATCH` | Oracle converts the zero length string to NULL before `NVL` and `DECODE` see it, so an empty requester behaves exactly like a missing one. |
| `create_publishes_package_state` | `pkg_order_mgmt.g_last_order_id` equals the OUT parameter | The procedure assigns the package variable from its dynamic SQL lookup and never clears it, so the value is readable by the next caller in the session. |
| `create_duplicate_raises_20901` | `SQLCODE` = -20901, message contains `Order number already exists` | `uk_orders_number` raises `DUP_VAL_ON_INDEX`, which the handler converts with `RAISE_APPLICATION_ERROR(-20901, ...)`. |
| `create_duplicate_leaves_no_row` | Exactly one row remains with that order number | The handler runs `ROLLBACK TO before_order`, which discards the failed insert and keeps the earlier successful one. |
| `create_failure_keeps_state` | `g_last_order_id` still holds the id from the successful call | Package variables are session state. The savepoint rollback inside the handler does not touch them. |
| `create_untrimmed_number_fails` | `SQLCODE` = 100 and no row named `UT-OM-09` survives | `trg_orders_bi` stores the trimmed upper case number, then the procedure looks the row up by the raw argument, gets `NO_DATA_FOUND`, and the `WHEN OTHERS` branch rolls back to the savepoint and re-raises unchanged. |

### add_order_line

| Test | Expected result | Reason |
| --- | --- | --- |
| `add_line_numbers_sequentially` | Lines 1 and 2 with amounts 10.00 and 39.98 | Line numbers come from `NVL(MAX(line_number), 0) + 1` computed per call, so they are dense and gap free as long as no concurrent session inserts. |
| `add_line_computes_extended` | `extended_amount` = 59.97, `discount_rate` = 0 | The amount is `p_quantity * p_unit_price` with no rounding needed at two decimals. The procedure writes a hard coded zero discount and ignores `price_tiers` completely. |
| `add_line_null_quantity_is_one` | `quantity` = 1, `extended_amount` = 12.34 | `NVL(p_quantity, 1)` inside the insert, so a NULL quantity is silently treated as one unit rather than rejected. |
| `add_line_null_price_raises` | `SQLCODE` = -1400 | `order_lines.unit_price` is `NOT NULL` and the procedure has no handler, so the storage error reaches the caller untranslated. |
| `add_line_sets_order_totals` | subtotal 59.97, discount 0, tax 4.95, total 64.92 | The `AFTER INSERT` trigger writes subtotal and total with no tax, then the procedure calls `refresh_order_total`, which overwrites both. Tax is `ROUND(59.97 * 0.0825, 2)` = `ROUND(4.947525, 2)`. |

### refresh_order_total

| Test | Expected result | Reason |
| --- | --- | --- |
| `refresh_rounds_tax_half_up` | tax 0.83, total 10.83 | `10.00 * 0.0825` is exactly 0.825 and Oracle `ROUND` is half away from zero, so it goes up. This is the single most likely value to move in a conversion. |
| `refresh_rounds_discount_first` | subtotal 59.97, discount 19.99, tax 3.30, total 43.28 | `59.97 * 33.33 / 100` is 19.988001, but the local variable is declared `orders.discount_amount%TYPE`, that is `NUMBER(14,2)`, so PL/SQL rounds on assignment and the tax is computed from 19.99: `ROUND(39.98 * 0.0825, 2)` = `ROUND(3.29835, 2)`. |
| `refresh_order_without_lines` | subtotal, discount, tax and total all 0 | The aggregate query returns a single row of `NVL`ed zeros when there are no lines, and the update writes those zeros over whatever the order carried. |
| `refresh_unknown_order_is_silent` | No exception, no row created for order 99902 | The aggregate still returns one row, the update matches nothing, and the procedure returns normally. A missing order is not an error here. |

### list_customer_orders

| Test | Expected result | Reason |
| --- | --- | --- |
| `list_first_page` | Orders 93007 then 93006 | `ORDER BY ordered_at DESC` inside the inner query, rows 1 and 2 of the `ROWNUM` window. |
| `list_second_page` | Orders 93005 then 93004 | Rows 3 and 4 of the same window. |
| `list_partial_last_page` | Order 93003 only | Rows 5 and 6 exist only up to row 5, so the last page is short rather than padded or wrapped. |
| `list_null_paging_defaults` | All five customer 90001 orders, newest first | `NVL(p_page_number, 1)` and `NVL(p_page_size, 25)`, so the window is rows 1 to 25. |
| `list_zero_page_size` | Empty cursor | The end row becomes 0, the inner predicate is `ROWNUM <= 0` and no row can qualify. No error is raised. |
| `list_unknown_customer` | Empty cursor | Nothing matches customer 99901. The OUT cursor is still opened, so callers must fetch, not check for NULL. |

### load_order_totals

| Test | Expected result | Reason |
| --- | --- | --- |
| `load_totals_populates_gtt` | Five rows: (93003, 0, 0), (93004, 1, 100.00), (93005, 1, 59.97), (93006, 1, 0), (93007, 2, 31.01) | One `gtt_order_totals` row per order of customer 90001, with the line count from a correlated subquery and the total copied from `orders.total_amount`. |
| `load_totals_null_total_is_zero` | Row for 93004 has `calculated_total` = 0 | `NVL(total_amount, 0)` in the collect step. A NULL total can be created by a direct update because the check constraint permits NULL and the insert trigger does not fire. |
| `load_totals_clears_previous` | The pre-seeded row for 99902 is gone | The procedure deletes the whole temp table before loading, so it is a full replace and not an accumulation. |
| `load_totals_unknown_customer` | Temp table empty, no exception | `BULK COLLECT` yields an empty collection and `FORALL` over an empty range is a no-op. Callers get success, not a "not found" signal. |

### summarize_order

| Test | Expected result | Reason |
| --- | --- | --- |
| `summarize_reports_line_count` | Output contains `lines=2 marker=LINE-1` | Order 93007 has two lines. The marker is written inside a `FOR i IN REVERSE 1 .. 2` loop, so the surviving value is always the one from the last iteration, that is `LINE-1`. |
| `summarize_order_without_invoice` | Output contains `order=93010 invoice=NONE` and `lines=1 marker=LINE-1` | The legacy `(+)` outer join keeps the order row when no invoice exists, and the `NVL` prints `NONE`. |
| `summarize_order_with_invoice` | Output contains `invoice=94001` | Order 93007 carries fixture invoice 94001 through the same outer join. |

### Trigger maintained values

| Test | Expected result | Reason |
| --- | --- | --- |
| `trigger_normalizes_order_number` | Generated id not null, `order_number` = `UT-TRIGGER-1`, status `OPEN`, total 0 | `trg_orders_bi` assigns the sequence key, applies `UPPER(TRIM(...))` to the number and `NVL`s status and total. All four are invisible to application code. |
| `trigger_leaves_extended_amount` | `extended_amount` stays 59.97 and `orders.subtotal_amount` stays 59.97 after the quantity is changed to 10 | The `AFTER UPDATE` trigger re-sums `extended_amount`, but nothing recomputes `extended_amount` itself from quantity and price, so a quantity change leaves the money stale and consistent with the old amount. |

## pkg_billing

### issue_invoice

| Test | Expected result | Reason |
| --- | --- | --- |
| `issue_creates_issued_invoice` | Invoice with status `ISSUED`, `invoice_total` 100.00, `order_id` 93010 | The total is copied from `orders.total_amount` at issue time. The invoice does not recompute anything from the lines. |
| `issue_numbers_from_sequence` | `invoice_number` = `INV-` followed by the invoice id | The number is built from `seq_invoices.NEXTVAL` and the key from `CURRVAL`, so the two agree within a call. Environment dependent in the digits only. |
| `issue_rounds_tax_on_insert` | `tax_total` = 4.95 for order 93005 | The procedure inserts `59.97 * 0.0825` = 4.947525 with no `ROUND`. The `NUMBER(14,2)` column does the rounding on the way in. |
| `issue_due_on_is_plus_30_days` | `TRUNC(due_on) - TRUNC(issued_on)` = 30 and both carry the same `HH24:MI:SS` | `SYSDATE + 30` adds whole days and keeps the time of day, because `DATE` here is a timestamp with second precision. Environment dependent in the absolute values. |
| `issue_writes_audit_row` | One `audit_log` row, `entity_name` `INVOICE`, `action_code` `ISSUED`, payload `INV-<id>`, `actor_name` not null | `write_billing_log` is called after the insert. `actor_name` comes from `SYS_CONTEXT`, which is populated for any logged in session, so the `NVL` to `BATCH` is unreachable in practice. |
| `issue_audit_row_is_committed` | After `ROLLBACK`: zero invoice rows, one audit row | `write_billing_log` carries `PRAGMA AUTONOMOUS_TRANSACTION` and commits its own transaction, so the audit trail outlives the rollback of the work it describes. |
| `issue_unknown_order_raises` | `SQLCODE` = -20911, message contains `Invoice creation failed` | The `WHEN OTHERS` handler converts every failure, including `NO_DATA_FOUND`, into the same estate error. Callers cannot distinguish causes except by parsing text. |
| `issue_second_invoice_raises` | `SQLCODE` = -20911 | `uk_invoices_order` allows one invoice per order, and the handler flattens the unique violation into the same code as above. |

### apply_payment

| Test | Expected result | Reason |
| --- | --- | --- |
| `payment_full_marks_paid` | Invoice 94001 becomes `PAID`, the new payment row is `CAPTURED` with method `CARD` | 10.00 was already captured, and 10.00 plus 21.01 reaches the 31.01 total, so the closing update sets `PAID`. |
| `payment_short_marks_partial` | Invoice status `PARTIAL` | 15.00 captured against a 31.01 total leaves a balance, and the `CASE` picks `PARTIAL`. |
| `payment_ignores_reversed` | Invoice status `PARTIAL` | The captured sum filters on `payment_status = 'CAPTURED'`, so the 5.00 `REVERSED` fixture payment is excluded. Counting it would have produced `PAID`, which is what makes this test discriminating. |
| `payment_null_method_is_unknown` | `payment_method` = `UNKNOWN` | `NVL(p_method, 'UNKNOWN')`. |
| `payment_empty_method_is_unknown` | `payment_method` = `UNKNOWN` | Oracle folds `''` to NULL before `NVL` runs. This is one of the assertions that is expected to fail on PostgreSQL. |
| `payment_on_void_invoice` | Payment row `PENDING`, invoice 94002 ends as `PAID` | The `DECODE` parks payments against a `VOID` invoice as `PENDING`, and the trigger on `payments` also protects `VOID`, but the unconditional update at the end of the procedure overwrites the status anyway. The procedure undoes its own trigger's protection. |
| `payment_unknown_invoice_raises` | `SQLCODE` = -20912, message contains `Invoice does not exist` | The explicit existence check runs before any insert. |
| `payment_zero_amount_raises` | `SQLCODE` = -2290 | `ck_payments_amount` requires a positive amount, and the handler ends in a bare `RAISE`, so the constraint error is not translated. |
| `payment_null_amount_raises` | `SQLCODE` = -1400 | `payments.amount_paid` is `NOT NULL`, again re-raised unchanged. |
| `payment_writes_audit_row` | One `audit_log` row with `action_code` `PAYMENT` and a payload matching `paid=%21%01%method=CARD` | The payload is built with `TO_CHAR(p_amount)` and no format model, so the decimal separator and any leading space follow the session NLS settings. Environment dependent, which is why the test matches a pattern. |

### rebuild_invoice_totals

| Test | Expected result | Reason |
| --- | --- | --- |
| `rebuild_sums_and_taxes_lines` | Invoice 94003 total 100.00, `tax_total` 8.25, line 94501 tax 8.25 | Lines are 100.00, NULL and 0.00. Each line is taxed at 8.25 percent and the invoice tax is the sum of the line taxes. |
| `rebuild_null_line_is_zero` | Line 94502 tax 0 and line 94503 tax 0 | `NVL` is applied both in the dynamic select and again in the loop, so a NULL line amount produces a stored zero rather than a NULL. |
| `rebuild_without_lines_zeroes` | Invoice 94001 total 0 and `tax_total` 0 | With no `invoice_lines` rows the sums are zero and the procedure writes them over the existing 31.01. Destructive by design in the source, and worth pinning because it looks like a bug and may get "fixed" during conversion. |
| `rebuild_reports_issued_label` | Output matches `rebuilt INV-<new invoice id> total=%` | `g_run_label` is package state written by `issue_invoice` and read by `rebuild_invoice_totals`. Nothing passes it between the calls, so the output of the second procedure depends on the history of the session. |
| `rebuild_label_survives_rollback` | After rolling back the invoice, the output still names the rolled back invoice number | Package state is session scoped, not transaction scoped. The label refers to a row that no longer exists. |

## pkg_customer_hier

### descendant_count

| Test | Expected result | Reason |
| --- | --- | --- |
| `count_includes_the_root` | 7 for root 90001 | The `CONNECT BY` walk includes the start row, so the count is the root plus its six descendants despite the name. |
| `count_of_subtree` | 5 for 90002 | `REGION-NORTH`, `BRANCH-N1`, `BRANCH-N2`, `DEPT-N1A`, `TEAM-N1A1`. |
| `count_of_leaf_is_one` | 1 for 90007 | A leaf still counts itself. |
| `count_unknown_root_is_zero` | 0 for 99901 | `COUNT(*)` over an empty `IN` list. No `NO_DATA_FOUND`, no NULL. |
| `count_null_root_is_zero` | 0 for a NULL argument | `START WITH customer_id = NULL` selects no start row, so the walk never begins. Callers cannot tell this apart from an unknown id. |
| `count_raises_on_loop` | `SQLCODE` = -1436 once two customers point at each other | The query has no `NOCYCLE`, so a cyclic parent link is a hard error rather than a truncated walk. The foreign key does not prevent the cycle. |

### print_tree

| Test | Expected result | Reason |
| --- | --- | --- |
| `tree_indents_and_orders` | Exactly these seven lines: `ROOT-CO level=1`, `  REGION-NORTH level=2`, `    BRANCH-N1 level=3`, `      DEPT-N1A level=4`, `        TEAM-N1A1 level=5`, `    BRANCH-N2 level=3`, `  REGION-SOUTH level=2` | Depth first traversal with `ORDER SIBLINGS BY customer_code` and two spaces of indent per level. Level 1 has no indent because `LPAD(' ', 0)` returns NULL on Oracle and `NULL || code` is just the code. |
| `tree_unknown_root_is_silent` | No output at all for root 99901 | The cursor loop body never executes and the procedure raises nothing. Silence is the only signal a caller gets. |
| `tree_ignores_status` | Starting at 90004, output contains `DEPT-N1A level=2` and `TEAM-N1A1 level=3` even though 90006 has status `H` | Neither `print_tree` nor `descendant_count` filters on status, so held and inactive nodes stay in the tree and do not cut off their children. |

### list_ancestors

| Test | Expected result | Reason |
| --- | --- | --- |
| `ancestors_self_then_parents` | Five rows for 90007: (90007, 1), (90006, 2), (90004, 3), (90002, 4), (90001, 5) | `CONNECT BY PRIOR parent_customer_id = customer_id` walks upwards, so `LEVEL` 1 is the customer itself and the root has the largest depth. `ORDER BY depth` makes the order part of the contract. |
| `ancestors_of_root_is_self` | One row, (90001, 1) | A customer with a NULL parent still returns itself. |
| `ancestors_unknown_is_empty` | Empty cursor for 99901 | An opened cursor with no rows, again with no error. |

### find_unordered_customers

| Test | Expected result | Reason |
| --- | --- | --- |
| `unordered_lists_quiet_actives` | Nine fixture customers: 90001, 90002, 90003, 90004, 90005, 90007, 90008, 90011, 90012, and specifically not 90009 | Ten fixture customers have status `A`, and the `MINUS` removes 90009 because its order is ten days old. 90008 stays because its only order is 100 days old, outside the `SYSDATE - 90` window. |
| `unordered_drops_new_orderer` | 90001 present before an order dated yesterday is inserted, absent afterwards, and the total drops by exactly one | The 90 day window is evaluated at query time against `SYSDATE`, so the result set is a function of the clock. |
| `unordered_ignores_non_active` | 90006 and 90010 never appear | 90006 is `H` and 90010 is `I`. Both are excluded by the status filter, not by their order history. Neither has any order at all. |

### Empty strings and trigger maintained values

| Test | Expected result | Reason |
| --- | --- | --- |
| `empty_channel_is_null` | Customer 90011 has `preferred_channel IS NULL`, and a fresh insert of `''` is also stored as NULL | Oracle stores the zero length string as NULL, so `ck_customers_channel` (`preferred_channel <> ''`) evaluates to UNKNOWN and the row is accepted. The constraint can never reject anything on Oracle. |
| `trigger_normalizes_code` | Customer 90012 reads back as `MIXED-CASE`, and a new row inserted as `'  ut-trigger-c  '` with a NULL status reads back as `UT-TRIGGER-C` with status `A` | `trg_customers_bi` applies `UPPER(TRIM(...))` to the code, defaults the status and assigns the sequence key. |

## Where PostgreSQL will legitimately differ

Each row is a place where a faithful, idiomatic PostgreSQL port produces a
different observable result. The decision column is what the customer DBA has to
settle before conversion, because both answers are defensible.

| # | Oracle behaviour | PostgreSQL behaviour | Tests affected | Decision required |
| --- | --- | --- | --- | --- |
| 1 | `''` is NULL, so `NVL(p_requested_by, 'BATCH')` yields `BATCH` and `preferred_channel <> ''` is UNKNOWN | `''` is a value: `coalesce('', 'BATCH')` yields `''`, and the check constraint rejects the row | `create_empty_requester_is_batch`, `payment_empty_method_is_unknown`, `empty_channel_is_null`, fixture rows 90011 and 93009 | Either normalize empty strings to NULL on the way in (trigger or application layer) and keep the Oracle result, or accept the new behaviour and clean the data. Pick one and apply it everywhere. |
| 2 | `ROUND` is half away from zero, and assignment to a `NUMBER(14,2)` variable rounds silently mid-computation | `round(numeric)` is also half away from zero, but `double precision` rounds half to even, and no rounding happens on assignment to an untyped `numeric` variable | `refresh_rounds_tax_half_up`, `refresh_rounds_discount_first`, `issue_rounds_tax_on_insert`, `add_line_sets_order_totals` | Declare every money variable as `numeric(14,2)` and never as `double precision`, or add explicit `round(..., 2)` at each step. Decide whether the mid-computation rounding of the discount is intended behaviour or a latent bug to fix at cutover. |
| 3 | `DATE` carries a time of day, and `SYSDATE + 30` keeps it | `date` has no time; `timestamp` does, and `+ 30` on a timestamp needs `interval '30 days'` | `issue_due_on_is_plus_30_days`, `unordered_drops_new_orderer`, every fixture using `SYSDATE` arithmetic | Map Oracle `DATE` to `timestamp(0)` and not to `date`, or accept that times of day are lost. This changes `due_on` comparisons and the 90 day window at the boundary. |
| 4 | `ROWNUM` in a nested query implements pagination, and `ROWNUM <= 0` is simply empty | `LIMIT` and `OFFSET`, or `row_number()`, and a negative or zero `LIMIT` is an error | `list_first_page`, `list_second_page`, `list_partial_last_page`, `list_null_paging_defaults`, `list_zero_page_size` | Reproduce the "page size 0 returns nothing quietly" behaviour explicitly, or start raising an error and fix the callers. Also decide the tie break for equal `ordered_at` values, which Oracle leaves unspecified today. |
| 5 | `CONNECT BY` with `LEVEL` and `ORDER SIBLINGS BY`, and a cycle raises ORA-01436 | Recursive CTE with a manual depth column, and a cycle loops forever unless `CYCLE` or a depth guard is added | `count_*`, `tree_*`, `ancestors_*` | Add an explicit cycle guard in the recursive CTE and decide the error contract: keep failing loudly like ORA-01436, or truncate the walk. Sibling ordering has to be reproduced with an ordering column, it is not automatic. |
| 6 | `LPAD(' ', 0)` returns NULL, and `NULL \|\| code` is `code` | `lpad(' ', 0)` returns `''`, and concatenation with NULL yields NULL | `tree_indents_and_orders` | The level 1 line happens to look identical, but any expression that relies on NULL concatenation absorbing a NULL will change. Audit the reporting code for the same pattern rather than assuming this one case is representative. |
| 7 | `PRAGMA AUTONOMOUS_TRANSACTION` lets `write_billing_log` commit inside a failed transaction | No autonomous transactions. A `dblink` loopback, a background worker or a plain insert in the caller's transaction | `issue_audit_row_is_committed`, `issue_writes_audit_row`, `payment_writes_audit_row` | Decide whether audit rows must survive a rollback. If yes, provision the loopback mechanism and its connection cost. If no, accept that the audit trail becomes transactional and stops recording attempts that failed. |
| 8 | Package variables (`g_last_order_id`, `g_run_label`) are session state that survives rollback | No package state. Schema variables are not available in older majors, so the usual replacements are a session temp table, a `GUC` or explicit parameters | `create_publishes_package_state`, `create_failure_keeps_state`, `rebuild_reports_issued_label`, `rebuild_label_survives_rollback` | Choose the replacement and confirm it also survives rollback. A temp table does not, unless it is `ON COMMIT PRESERVE ROWS`. Passing the value as a parameter is cleaner but changes the public API. |
| 9 | `MINUS` deduplicates and in practice returns sorted output | `EXCEPT` deduplicates and guarantees no order at all | `unordered_lists_quiet_actives`, `unordered_ignores_non_active` | Add an explicit `ORDER BY` if any consumer depends on the order. The tests here deliberately compare sets, so they do not lock the current ordering in. |
| 10 | A global temporary table with `ON COMMIT DELETE ROWS` is defined once and visible to every session | `CREATE TEMPORARY TABLE` is per session, and the table has to be created before first use in that session | `load_totals_populates_gtt`, `load_totals_null_total_is_zero`, `load_totals_clears_previous`, `load_totals_unknown_customer` | Create the temp table at connection setup, or switch to an unlogged permanent table keyed by session. Connection poolers make this decision load bearing, so settle it early. |
| 11 | The legacy `(+)` outer join syntax | Only `LEFT JOIN` | `summarize_order_without_invoice`, `summarize_order_with_invoice`, the reporting views | Mechanical rewrite, but each `(+)` has to be checked for the mixed inner and outer predicates Oracle silently allowed. |
| 12 | Row level `BEFORE INSERT` triggers assign keys from sequences and normalize values | Identity or `DEFAULT nextval(...)` columns plus optional triggers | `trigger_normalizes_order_number`, `trigger_normalizes_code`, and every test that reads back a generated key | Decide whether normalization stays in the database. If it moves to the application, the values written by existing batch jobs and by direct SQL will start to differ. |
| 13 | `TO_CHAR(number)` with no format model follows NLS and may include a leading space | `to_char` needs an explicit format model, and casting to `text` produces different text | `payment_writes_audit_row`, `issue_numbers_from_sequence` | Pin an explicit format model at conversion time. Audit payloads are compared by downstream tooling, so a change in spacing is a real interface change. |
| 14 | `DUP_VAL_ON_INDEX`, `NO_DATA_FOUND` and constraint errors are flattened into ORA-20901 and ORA-20911 by `WHEN OTHERS` | `unique_violation`, `no_data_found` and friends are distinct SQLSTATEs | `create_duplicate_raises_20901`, `create_untrimmed_number_fails`, `issue_unknown_order_raises`, `issue_second_invoice_raises`, `payment_zero_amount_raises`, `payment_null_amount_raises` | Keep the flattened estate codes for the sake of existing callers, or expose real SQLSTATEs and update every caller that pattern matches on ORA numbers. |

## What this suite does not cover

Stated plainly so that signoff is informed:

- Concurrency. `add_order_line` computes the next line number with a read then an
  insert, which is a lost update waiting to happen. That needs a two session
  test, which utPLSQL alone cannot express.
- Performance and plans. Nothing here asserts index usage, and the
  index-organized `order_lines` table is a migration decision on its own.
- `views/001_reporting_views.sql` is exercised only indirectly. If the views are
  part of the customer facing contract, they need their own suite.
- NLS dependent formatting is asserted by pattern, not by exact text, so a change
  in the decimal separator would not be caught.
- Nothing has been run. See the provenance section at the top.
