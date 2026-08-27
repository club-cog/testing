# Business rules extracted from the Oracle estate

Labels mean:

- **Confirmed**: the rule is directly implemented by the supplied source.
- **Ambiguous**: the source implements something, but its intended business meaning is not clear.
- **Likely bug**: the implementation conflicts with another rule, appears unable to run as written, or produces a suspicious result. This label is an assessment, not proof from production behavior.

## Customer and address rules

| ID | Rule in plain language | Status | Source |
|---|---|---|---|
| CUST-01 | A customer code is required and unique. On insert, it is trimmed and converted to uppercase. | Confirmed | `ddl/001_tables.sql:6`, `19-20`; `triggers/001_key_assignment.sql:3-13` |
| CUST-02 | A missing customer identifier is allocated from `SEQ_CUSTOMERS`; a supplied identifier is accepted. | Confirmed | `triggers/001_key_assignment.sql:7-9` |
| CUST-03 | Customer status may be `A`, `I`, or `H`. Missing status becomes `A` on insert. The meanings of the letters are not defined in the source. | Ambiguous | `ddl/001_tables.sql:8-9`; `triggers/001_key_assignment.sql:12` |
| CUST-04 | Credit limit may be absent but cannot be negative when present. | Confirmed | `ddl/001_tables.sql:12`, `23` |
| CUST-05 | Customers can form a parent-child hierarchy. The database does not prevent a customer from being its own parent or forming a longer cycle. | Likely bug | `ddl/001_tables.sql:15`, `21-22` |
| CUST-06 | `PREFERRED_CHANNEL` defaults to Oracle null even though the source spells the default as an empty string. Its check does not require a value or define valid channels. | Ambiguous | `ddl/001_tables.sql:10-11`, `27-28` |
| CUST-07 | The tree-print routine starts at the requested customer, walks descendants, numbers the root as level 1, indents each level by two spaces, and sorts siblings by customer code. | Confirmed | `packages/pkg_customer_hier.pkb:7-22` |
| CUST-08 | The ancestor routine returns the requested customer as depth 1 and then walks toward parents. | Confirmed | `packages/pkg_customer_hier.pkb:25-36` |
| CUST-09 | `DESCENDANT_COUNT` includes the root customer in the returned count. The function name could be read as excluding the root. | Ambiguous | `packages/pkg_customer_hier.pkb:53-69` |
| CUST-10 | Active customers are considered "unordered" when they have no order timestamp in the preceding 90 days. | Confirmed | `packages/pkg_customer_hier.pkb:38-51` |
| CUST-11 | A missing address identifier is allocated from `SEQ_ADDRESSES`; a supplied identifier is accepted. | Confirmed | `triggers/001_key_assignment.sql:20-22` |
| CUST-12 | Address kind may be `BILL`, `SHIP`, or `OTHER`, and defaults to `SHIP`, but null is still allowed. | Confirmed | `ddl/001_tables.sql:33`, `46` |
| CUST-13 | Country code is uppercased on insert and defaults to `ZZ` when null. The source does not establish whether values must be ISO country codes. | Ambiguous | `ddl/001_tables.sql:39`; `triggers/001_key_assignment.sql:23` |
| CUST-14 | `VALIDATED_FLAG` defaults to Oracle null, and the check does not define any legal nonempty values. | Likely bug | `ddl/001_tables.sql:40-41` |
| CUST-15 | An order's bill and ship address only have to exist. They are not required to belong to the order's customer. | Likely bug | `ddl/001_tables.sql:87-89`, `102-107` |

## Product and price rules

| ID | Rule in plain language | Status | Source |
|---|---|---|---|
| PROD-01 | A product SKU is required and unique. On insert, it is trimmed and converted to uppercase. | Confirmed | `ddl/001_tables.sql:51`, `62-64`; `triggers/001_key_assignment.sql:27-35` |
| PROD-02 | A missing product identifier is allocated from `SEQ_PRODUCTS`; a supplied identifier is accepted. | Confirmed | `triggers/001_key_assignment.sql:31-33` |
| PROD-03 | Product active flag may be `Y` or `N` and defaults to `Y`, but null is allowed. | Confirmed | `ddl/001_tables.sql:54-55` |
| PROD-04 | Base price cannot be negative. | Confirmed | `ddl/001_tables.sql:56`, `64` |
| PROD-05 | Price tiers are unique by product and tier code. Minimum quantity defaults to 1 and must be positive. | Confirmed | `ddl/001_tables.sql:69-72`, `79-80` |
| PROD-06 | A price tier's end timestamp cannot precede its start timestamp. Overlapping tiers for the same product are allowed by the DDL. | Confirmed | `ddl/001_tables.sql:73-74`, `81` |
| PROD-07 | No included order routine looks up product base price, active state, or price tiers. The caller supplies the line price. | Ambiguous | `packages/pkg_order_mgmt.pkb:54-84`; `app/order_worker.py:16-22` |
| PROD-08 | `SEQ_PRICE_TIERS` exists, but the included source does not assign it to `PRICE_TIERS.TIER_ID`. | Ambiguous | `ddl/002_sequences_indexes.sql:7`; no caller found in the estate |

## Order creation and line rules

| ID | Rule in plain language | Status | Source |
|---|---|---|---|
| ORD-01 | A missing order identifier is allocated from `SEQ_ORDERS`; a supplied identifier is accepted. | Confirmed | `triggers/001_key_assignment.sql:42-44` |
| ORD-02 | Order number is required and unique. On insert, it is trimmed and converted to uppercase. A duplicate raised through `CREATE_ORDER` becomes application error `-20901`. | Confirmed | `ddl/001_tables.sql:86`, `100-101`; `triggers/001_key_assignment.sql:46`; `packages/pkg_order_mgmt.pkb:45-48` |
| ORD-03 | `CREATE_ORDER` stores requester `BATCH` and status `OPEN` when the requester is null or Oracle empty string. A non-`BATCH` requester produces status `HELD`. | Confirmed | `packages/pkg_order_mgmt.pkb:18-35` |
| ORD-04 | Direct order inserts default status to `OPEN`, while package inserts can choose `HELD`. | Confirmed | `ddl/001_tables.sql:90`; `triggers/001_key_assignment.sql:47`; `packages/pkg_order_mgmt.pkb:18-35` |
| ORD-05 | Allowed order statuses are `OPEN`, `HELD`, `READY`, `CLOSED`, and `VOID`. The included source contains no transition rules among them. | Ambiguous | `ddl/001_tables.sql:90`, `108-110` |
| ORD-06 | `CREATE_ORDER` sets a savepoint and rolls back only to that point on an error. Commit remains the application's responsibility. | Confirmed | `packages/pkg_order_mgmt.pkb:15`, `45-51`; `app/dao.py:41-48` |
| ORD-07 | The package records the most recently created order identifier and a call count in Oracle session state and writes both to `DBMS_OUTPUT`. | Confirmed | `packages/pkg_order_mgmt.pks:2`; `packages/pkg_order_mgmt.pkb:3`, `16`, `38-44` |
| ORD-08 | The raw application query can advance `SEQ_ORDERS` only to propose an `ORD-<number>` value, without creating an order row. Gaps are therefore expected. | Confirmed | `app/raw_queries.sql:34-35` |
| ORD-09 | An order line number is one greater than the current maximum for that order. | Confirmed | `packages/pkg_order_mgmt.pkb:62-65` |
| ORD-10 | Concurrent line additions can select the same next line number and race on the primary key. | Likely bug | `packages/pkg_order_mgmt.pkb:62-84`; `ddl/001_tables.sql:125` |
| ORD-11 | Line quantity defaults to 1 and must be positive. Fractional values remain possible because the type has no scale. | Ambiguous | `ddl/001_tables.sql:120`, `130`; `packages/pkg_order_mgmt.pkb:80`, `83` |
| ORD-12 | `ADD_ORDER_LINE` always sets discount rate to zero and sets extended amount to quantity times caller-supplied unit price. | Confirmed | `packages/pkg_order_mgmt.pkb:67-84` |
| ORD-13 | Product price and active state are not checked when a line is added. | Ambiguous | `packages/pkg_order_mgmt.pkb:54-84` |
| ORD-14 | Updating quantity, unit price, or discount rate does not recompute `EXTENDED_AMOUNT`. The total trigger sums the existing extended amount. | Likely bug | `triggers/002_derived_values.sql:1-16`; no source updates `EXTENDED_AMOUNT` on those changes |
| ORD-15 | Direct deletion of an order line does not refresh parent totals because the trigger handles only insert and selected updates. | Likely bug | `triggers/002_derived_values.sql:1-2` |
| ORD-16 | The line trigger queries `ORDER_LINES` from an `AFTER EACH ROW` trigger on `ORDER_LINES`, which is expected to raise Oracle mutating-table error `ORA-04091`. | Likely bug | `triggers/002_derived_values.sql:1-16` |
| ORD-17 | `REFRESH_ORDER_TOTAL` defines subtotal as the sum of extended amount, discount as the sum of extended amount times discount rate, tax as 8.25 percent of subtotal less discount rounded to cents, and total as subtotal less discount plus tax. | Confirmed | `packages/pkg_order_mgmt.pkb:89-109` |
| ORD-18 | The line trigger defines subtotal and total as the raw sum of extended amount and does not update discount or tax. This conflicts with `REFRESH_ORDER_TOTAL`. | Likely bug | `triggers/002_derived_values.sql:5-16`; `packages/pkg_order_mgmt.pkb:96-109` |
| ORD-19 | Order total must be nonnegative, but subtotal, discount, and tax have no independent nonnegative checks. | Confirmed | `ddl/001_tables.sql:94-97`, `111` |
| ORD-20 | The application commits after every `ADD_ORDER_LINE` call, so an order with several lines can be partially committed if a later line fails. | Likely bug | `app/order_worker.py:16-22`; `app/dao.py:50-56` |

## Order query and work-table rules

| ID | Rule in plain language | Status | Source |
|---|---|---|---|
| QRY-01 | Customer order pages default null page number to 1, null page size to 25, and sort newest `ORDERED_AT` first. | Confirmed | `packages/pkg_order_mgmt.pkb:112-143` |
| QRY-02 | Page number and page size are not validated as positive. Zero or negative inputs calculate invalid row ranges. | Likely bug | `packages/pkg_order_mgmt.pkb:118-121` |
| QRY-03 | Orders with equal `ORDERED_AT` values have no deterministic relative order, so they can move between pages. | Likely bug | `packages/pkg_order_mgmt.pkb:134-143` |
| QRY-04 | `V_RECENT_ORDERS` returns at most 50 orders after sorting by `ORDERED_AT` descending, again without a tie-breaker. | Confirmed | `views/001_reporting_views.sql:34-46` |
| QRY-05 | `LOAD_ORDER_TOTALS` clears the current session's temporary rows, then loads every order for one customer with a line count and the already stored order total. | Confirmed | `packages/pkg_order_mgmt.pkb:146-169` |
| QRY-06 | The work column is called `CALCULATED_TOTAL`, but the procedure copies `ORDERS.TOTAL_AMOUNT`; it does not calculate a total from lines. | Ambiguous | `packages/pkg_order_mgmt.pkb:157-167`; `ddl/001_tables.sql:205` |
| QRY-07 | Temporary work rows are deleted at commit. A later consumer must use the same database session and read before any commit. No included consumer exists. | Ambiguous | `ddl/001_tables.sql:202-207`; `packages/pkg_order_mgmt.pkb:146-174` |
| QRY-08 | `SUMMARIZE_ORDER` reports lines with null extended amounts and always produces a marker. With no lines it still sets the marker to `LINE-1`. | Ambiguous | `packages/pkg_order_mgmt.pkb:176-196`, `211` |
| QRY-09 | `SUMMARIZE_ORDER` emits one invoice summary row even when no invoice exists. | Confirmed | `packages/pkg_order_mgmt.pkb:198-209` |

## Invoice rules

| ID | Rule in plain language | Status | Source |
|---|---|---|---|
| INV-01 | There can be at most one invoice per order. | Confirmed | `ddl/001_tables.sql:150-152` |
| INV-02 | `ISSUE_INVOICE` creates an invoice number as `INV-` plus the next invoice sequence value and uses that same value as the invoice identifier. | Confirmed | `packages/pkg_billing.pkb:51-53`, `58-80` |
| INV-03 | Invoice number is required and unique and is trimmed and uppercased on insert. | Confirmed | `ddl/001_tables.sql:139`, `148-150`; `triggers/001_key_assignment.sql:52-60` |
| INV-04 | An issued invoice is dated at `SYSDATE`, due exactly 30 days later, and starts in status `ISSUED`. | Confirmed | `packages/pkg_billing.pkb:58-79` |
| INV-05 | `ISSUE_INVOICE` copies the order's `TOTAL_AMOUNT` to `INVOICE_TOTAL`. It then sets `TAX_TOTAL` to 8.25 percent of that copied total. Since the order total already includes tax under `REFRESH_ORDER_TOTAL`, the tax meaning may be inconsistent. | Ambiguous | `packages/pkg_order_mgmt.pkb:102-109`; `packages/pkg_billing.pkb:46-49`, `75-78` |
| INV-06 | The invoice delivery note is the fixed text `Generated by legacy billing batch`. | Confirmed | `packages/pkg_billing.pkb:43-44`, `55-56`, `67-78` |
| INV-07 | Issuing an invoice writes an independent `ISSUED` audit event. That event can remain even if invoice creation later rolls back. | Confirmed | `packages/pkg_billing.pkb:82-94`; `5-35` |
| INV-08 | No included code creates `INVOICE_LINES`, although a sequence and rebuild routine exist for them. | Ambiguous | `ddl/001_tables.sql:158-170`; `ddl/002_sequences_indexes.sql:10`; no insert found |
| INV-09 | Invoice lines are unique by invoice and order-line number, but the database does not verify that the line belongs to the invoice's order. | Likely bug | `ddl/001_tables.sql:158-170`; `ddl/002_sequences_indexes.sql:27-28` |
| INV-10 | Rebuilding totals sets every invoice-line tax to 8.25 percent of line amount, invoice total to the sum of line amounts, and invoice tax total to 8.25 percent of that sum. | Confirmed | `packages/pkg_billing.pkb:155-183` |
| INV-11 | The rebuild rule differs from issue-time totals and does not add line tax into `INVOICE_TOTAL`. The intended tax-inclusive or tax-exclusive meaning is unclear. | Ambiguous | `packages/pkg_billing.pkb:46-78`, `170-183` |
| INV-12 | `REBUILD_INVOICE_TOTALS` prints a package run label left by the most recent invoice issued in the same Oracle session, or `UNSET`. The label need not refer to the invoice being rebuilt. | Likely bug | `packages/pkg_billing.pkb:3`, `82`, `155-187` |

## Payment rules

| ID | Rule in plain language | Status | Source |
|---|---|---|---|
| PAY-01 | A payment amount is required and must be greater than zero. | Confirmed | `ddl/001_tables.sql:178`, `187` |
| PAY-02 | Payment status may be `CAPTURED`, `PENDING`, or `REVERSED`. | Confirmed | `ddl/001_tables.sql:177`, `184-186` |
| PAY-03 | `APPLY_PAYMENT` locks the invoice row before reading captured payments and inserting the new payment. | Confirmed | `packages/pkg_billing.pkb:105-115` |
| PAY-04 | A null or Oracle empty payment method is stored as `UNKNOWN`. No controlled method list exists. | Confirmed | `packages/pkg_billing.pkb:117-132` |
| PAY-05 | If the invoice was `VOID`, the new payment is inserted as `PENDING`; otherwise it is inserted as `CAPTURED`. | Confirmed | `packages/pkg_billing.pkb:125-131` |
| PAY-06 | The package adds the requested amount to its running paid total even when the inserted payment status is `PENDING`. | Likely bug | `packages/pkg_billing.pkb:111-115`, `125-140` |
| PAY-07 | After any payment insert, the trigger preserves `VOID`, but the package then changes the invoice to `PAID` or `PARTIAL`. A payment attempt can therefore unvoid an invoice. | Likely bug | `triggers/002_derived_values.sql:20-27`; `packages/pkg_billing.pkb:134-141` |
| PAY-08 | An invoice becomes `PAID` when prior captured payments plus the requested amount are at least the invoice total; otherwise it becomes `PARTIAL`. | Confirmed | `packages/pkg_billing.pkb:111-141` |
| PAY-09 | Overpayment is allowed. The excess is not stored separately or rejected. | Ambiguous | `packages/pkg_billing.pkb:134-141`; no upper-bound constraint in `ddl/001_tables.sql:172-188` |
| PAY-10 | A payment writes an autonomous `PAYMENT` audit event containing amount and method. The audit can survive a later business rollback. | Confirmed | `packages/pkg_billing.pkb:143-153`; `5-35` |
| PAY-11 | The application commits invoice issuance before attempting payment. A payment failure leaves the invoice committed. | Confirmed | `app/order_worker.py:24-30`; `app/dao.py:86-99` |

## Audit rules

| ID | Rule in plain language | Status | Source |
|---|---|---|---|
| AUD-01 | Billing audit rows use entity name `INVOICE`, the invoice identifier, action `ISSUED` or `PAYMENT`, and the Oracle session user with `BATCH` fallback. | Confirmed | `packages/pkg_billing.pkb:12-29`, `83`, `143-147` |
| AUD-02 | Audit writes commit independently from invoice and payment work. | Confirmed | `packages/pkg_billing.pkb:10`, `30` |
| AUD-03 | Any audit error is rolled back and ignored. Business operations continue without an audit record. | Confirmed | `packages/pkg_billing.pkb:31-35` |
| AUD-04 | The schema contains an event fingerprint, but no included code populates it or uses it to prevent duplicate events. | Ambiguous | `ddl/001_tables.sql:198`; no reference found elsewhere |

## Reporting rules

| ID | Rule in plain language | Status | Source |
|---|---|---|---|
| RPT-01 | `V_ORDER_SUMMARY` includes every order with its required customer and optional invoice. Missing invoice status appears as `UNBILLED`, and missing invoice total appears as zero. | Confirmed | `views/001_reporting_views.sql:1-18` |
| RPT-02 | `V_CUSTOMER_BALANCE` intends to show every customer with invoice total, payment total, and the difference. | Confirmed | `views/001_reporting_views.sql:20-32` |
| RPT-03 | A customer with one invoice and multiple payments has the invoice total repeated once per payment before summing. Reported invoiced total and balance can therefore be overstated. | Likely bug | `views/001_reporting_views.sql:20-32` |
| RPT-04 | The materialized rollup includes customers with no orders, counts orders, sums stored order totals, and records the latest order timestamp. | Confirmed | `ddl/003_derived_objects.sql:5-17` |
| RPT-05 | The materialized rollup refreshes fully and only on demand. The included estate does not identify the refresh caller or freshness expectation. | Ambiguous | `ddl/003_derived_objects.sql:5-8`; `docs/estate-notes.md:8-9` |
| RPT-06 | `CURRENT_ORDERS` is another name for the entire `ORDERS` table. It does not mean only open or current-status orders. | Ambiguous | `ddl/003_derived_objects.sql:3` |
| RPT-07 | The application date-range query uses an inclusive `BETWEEN` ending at `END_DATE + 1`, which includes the exact first instant after the intended end day if the bind contains midnight. | Likely bug | `app/raw_queries.sql:29-32` |

## Rules that need owner decisions before conversion

The following cannot be resolved safely from source alone:

1. Whether to preserve or correct the mutating line trigger and inconsistent order-total formulas.
2. Whether an invoice total is tax-inclusive, and what `TAX_TOTAL` represents.
3. Whether payments against `VOID` invoices are rejected, pending, or allowed to reopen the invoice.
4. Whether `DESCENDANT_COUNT` should include the root.
5. Whether customer status letters and placeholder codes such as `ZZ` have documented meanings.
6. Whether price tiers are used by omitted callers and how overlapping valid tiers are selected.
7. Whether invoice lines are loaded by an omitted process and how their identifiers are assigned.
8. Whether temporary order totals have an omitted reader that depends on commit-cleared session data.
9. Whether audit loss on logging error is accepted policy.
10. Whether the application intentionally commits each line, invoice, and payment as separate units.
