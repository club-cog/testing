# Oracle object inventory

## Scope and counting

This inventory covers every schema object created by the source files and every public routine declared in a package specification. Inline constraints and comments are documented in `04-data-dictionary.md`; they are not counted as separate entries because this estate does not create them with standalone statements.

The source defines 52 schema objects: 11 tables, 9 sequences, 13 explicit indexes, 1 synonym, 1 materialized view, 3 views, 8 triggers, 3 package specifications, and 3 package bodies. The package specifications expose 14 public routines, so the table below has 66 entries.

Line ranges refer to the files as assessed on the `oracle-estate-demo` branch.

## Inventory

| Object | Type | File | Lines | What it does in one line | Conversion complexity | Why that grade |
|---|---|---|---:|---|---|---|
| `CUSTOMERS` | Table | `ddl/001_tables.sql` | 4-24 | Stores customer identity, hierarchy, status, limits, notes, and binary attributes. | Medium | Self-reference, Oracle string length semantics, empty-string behavior, unbounded `NUMBER`, `DATE`, `CLOB`, `BLOB`, and `RAW` need explicit mappings. |
| `ADDRESSES` | Table | `ddl/001_tables.sql` | 30-47 | Stores customer billing, shipping, and other addresses. | Medium | Empty-string defaults, `DATE`, mixed byte and character limits, and insert-trigger normalization need preservation. |
| `PRODUCTS` | Table | `ddl/001_tables.sql` | 49-65 | Stores sellable products, prices, lifecycle dates, text, and images. | Medium | Unbounded `NUMBER`, `DATE`, LOB storage, and trigger normalization require decisions. |
| `PRICE_TIERS` | Table | `ddl/001_tables.sql` | 67-82 | Stores quantity-based product prices and validity windows. | Medium | Unbounded numeric quantity and timestamp-bearing `DATE` columns require target types and boundary rules. |
| `ORDERS` | Table | `ddl/001_tables.sql` | 84-112 | Stores order headers, addresses, status, money totals, notes, and source tokens. | Medium | Several triggers and packages maintain the row, while `DATE`, LOBs, `RAW`, and caller-supplied keys need coordinated choices. |
| `ORDER_LINES` | Table (IOT) | `ddl/001_tables.sql` | 116-135 | Stores order lines in primary-key order with an Oracle overflow segment. | High | PostgreSQL has no IOT equivalent, and storage, row identity, indexing, and update behavior must be redesigned. |
| `INVOICES` | Table | `ddl/001_tables.sql` | 137-156 | Stores one invoice per order, its dates, status, totals, PDF, and delivery note. | Medium | One-per-order behavior, `DATE`, LOB storage, and package-driven totals and statuses must remain consistent. |
| `INVOICE_LINES` | Table | `ddl/001_tables.sql` | 158-170 | Stores invoice line amounts and tax keyed by a generated line identifier. | Medium | Key generation is not implemented in the included code, and numeric meanings plus the missing order-line foreign key need review. |
| `PAYMENTS` | Table | `ddl/001_tables.sql` | 172-188 | Stores invoice payments, status, method, confirmation bytes, and gateway notes. | Medium | Package and trigger status logic overlap, while `DATE`, `RAW`, `CLOB`, and key generation need target decisions. |
| `AUDIT_LOG` | Table | `ddl/001_tables.sql` | 190-200 | Stores generic audit events written by billing code. | Medium | Autonomous writes, swallowed failures, `DATE`, LOB, binary data, and an unbounded entity identifier affect the target design. |
| `GTT_ORDER_TOTALS` | Global temporary table | `ddl/001_tables.sql` | 202-207 | Holds per-session order total work rows that are deleted at commit. | High | PostgreSQL temporary table lifetime and commit behavior differ, and connection pooling changes which session owns the data. |
| `SEQ_CUSTOMERS` | Sequence | `ddl/002_sequences_indexes.sql` | 4 | Supplies customer identifiers through a trigger. | Low | A PostgreSQL sequence or identity can preserve the behavior after ownership and explicit-ID policy are chosen. |
| `SEQ_ADDRESSES` | Sequence | `ddl/002_sequences_indexes.sql` | 5 | Supplies address identifiers through a trigger. | Low | The mechanism maps directly once trigger versus identity behavior is decided. |
| `SEQ_PRODUCTS` | Sequence | `ddl/002_sequences_indexes.sql` | 6 | Supplies product identifiers through a trigger. | Low | The mechanism maps directly once trigger versus identity behavior is decided. |
| `SEQ_PRICE_TIERS` | Sequence | `ddl/002_sequences_indexes.sql` | 7 | Reserves identifiers for price tiers, although no included caller uses it. | Low | PostgreSQL can create the sequence directly, but the missing assignment caller must be found before cutover. |
| `SEQ_ORDERS` | Sequence | `ddl/002_sequences_indexes.sql` | 8 | Supplies order identifiers and is also read directly by application SQL. | Medium | Trigger assignment and direct `NEXTVAL` use must share one target sequence without causing duplicate or skipped business numbers. |
| `SEQ_INVOICES` | Sequence | `ddl/002_sequences_indexes.sql` | 9 | Supplies invoice identifiers and invoice-number text in `PKG_BILLING`. | Medium | The package depends on `NEXTVAL` followed by session-local `CURRVAL`, plus a trigger accepts explicit identifiers. |
| `SEQ_INVOICE_LINES` | Sequence | `ddl/002_sequences_indexes.sql` | 10 | Reserves invoice-line identifiers, although no included caller uses it. | Low | The sequence maps directly, but the absent assignment path is an open dependency. |
| `SEQ_PAYMENTS` | Sequence | `ddl/002_sequences_indexes.sql` | 11 | Supplies payment identifiers directly inside `PKG_BILLING`. | Low | A direct PostgreSQL `nextval` or identity mapping is straightforward. |
| `SEQ_AUDIT_LOG` | Sequence | `ddl/002_sequences_indexes.sql` | 12 | Supplies audit identifiers in both a trigger and billing code. | Medium | Two assignment paths must remain compatible and sequence synchronization must be proved after data load. |
| `IX_CUSTOMERS_PARENT` | B-tree index | `ddl/002_sequences_indexes.sql` | 14 | Supports customer hierarchy traversal by parent. | Low | A PostgreSQL B-tree on the same column is the natural starting point. |
| `IX_ADDRESSES_CUSTOMER_KIND` | B-tree index | `ddl/002_sequences_indexes.sql` | 15 | Supports address lookup by customer and kind. | Low | The key order maps directly, subject to workload validation. |
| `IX_PRODUCTS_GROUP_ACTIVE` | B-tree index | `ddl/002_sequences_indexes.sql` | 16 | Supports product filtering by group and active flag. | Low | The index maps directly, though actual selectivity is unknown. |
| `IX_PRICE_TIERS_PRODUCT_QTY` | B-tree index | `ddl/002_sequences_indexes.sql` | 17 | Supports product price-tier lookup by minimum quantity. | Low | The ordered numeric key maps directly. |
| `IX_ORDERS_CUSTOMER_DATE` | B-tree index | `ddl/002_sequences_indexes.sql` | 18 | Supports newest-order lookup for a customer. | Low | PostgreSQL supports descending index keys and can use the same leading columns. |
| `IX_ORDERS_STATUS_DATE` | B-tree index | `ddl/002_sequences_indexes.sql` | 19 | Supports order filtering by status and newest date. | Low | The structure maps directly, but data distribution is unavailable. |
| `IX_ORDER_LINES_PRODUCT` | B-tree index | `ddl/002_sequences_indexes.sql` | 20 | Supports finding order lines by product. | Low | A PostgreSQL B-tree is equivalent for lookup purposes. |
| `IX_INVOICES_STATUS_DUE` | B-tree index | `ddl/002_sequences_indexes.sql` | 21 | Supports invoice status and due-date work queues. | Low | The key order maps directly after `due_on` receives a timestamp type. |
| `IX_PAYMENTS_INVOICE_DATE` | B-tree index | `ddl/002_sequences_indexes.sql` | 22 | Supports payment history lookup by invoice and time. | Low | The same PostgreSQL B-tree is a reasonable initial translation. |
| `IX_AUDIT_ENTITY_TIME` | B-tree index | `ddl/002_sequences_indexes.sql` | 23 | Supports audit lookup by entity, identifier, and time. | Low | The structure maps directly after identifier and timestamp types are fixed. |
| `BIX_ORDERS_STATUS` | Bitmap index | `ddl/002_sequences_indexes.sql` | 25 | Provides an Oracle bitmap index on low-cardinality order status. | High | PostgreSQL has no persistent bitmap index type; a B-tree, partial indexes, or no replacement must be selected from write and query evidence. |
| `UX_INVOICE_LINES_INVOICE_LINE` | Unique B-tree index | `ddl/002_sequences_indexes.sql` | 27-28 | Enforces one invoice-line record per invoice and order-line number. | Low | A PostgreSQL unique index preserves the declared key. |
| `CURRENT_ORDERS` | Synonym | `ddl/003_derived_objects.sql` | 3 | Gives legacy callers an alternate name for `ORDERS`. | Medium | PostgreSQL has no direct synonym object, so callers, a compatibility view, or schema search-path rules must change. |
| `MV_CUSTOMER_ORDER_ROLLUP` | Materialized view | `ddl/003_derived_objects.sql` | 5-17 | Stores an on-demand full customer order-count and total summary. | High | Refresh scheduling is missing, PostgreSQL refresh and locking differ, and concurrent refresh needs a qualifying unique index. |
| `IX_MV_CUSTOMER_ROLLUP_TOTAL` | B-tree index | `ddl/003_derived_objects.sql` | 19-20 | Supports ordering or filtering the rollup by order total. | Low | The index maps directly but does not satisfy PostgreSQL concurrent-refresh uniqueness requirements. |
| `V_ORDER_SUMMARY` | View | `views/001_reporting_views.sql` | 1-18 | Joins orders to customers and optional invoices for reporting. | Medium | Oracle `(+)` syntax and `NVL` require semantic rewrites, not textual substitutions. |
| `V_CUSTOMER_BALANCE` | View | `views/001_reporting_views.sql` | 20-32 | Aggregates invoiced, paid, and outstanding totals by customer. | High | Chained outer joins need rewriting, and multiple payments can multiply invoice totals before aggregation. |
| `V_RECENT_ORDERS` | View | `views/001_reporting_views.sql` | 34-46 | Returns the 50 most recently ordered rows. | Medium | The nested sort plus `ROWNUM` must become an ordered `LIMIT`, with a deterministic tie-breaker decision. |
| `TRG_CUSTOMERS_BI` | Trigger | `triggers/001_key_assignment.sql` | 3-13 | Assigns customer keys, normalizes codes, and defaults status before insert. | Medium | Identity behavior must still allow explicit keys, and Oracle empty-string and trim behavior affect validation. |
| `TRG_ADDRESSES_BI` | Trigger | `triggers/001_key_assignment.sql` | 16-24 | Assigns address keys and uppercases or defaults country code. | Medium | The normalization must be placed in a trigger, generated input path, or application contract. |
| `TRG_PRODUCTS_BI` | Trigger | `triggers/001_key_assignment.sql` | 27-35 | Assigns product keys and normalizes SKU text. | Medium | Key and normalization behavior must be preserved for every writer. |
| `TRG_ORDERS_BI` | Trigger | `triggers/001_key_assignment.sql` | 38-49 | Assigns order keys, normalizes numbers, and defaults status and total. | Medium | It overlaps table defaults and package behavior and must remain compatible with caller-supplied keys. |
| `TRG_INVOICES_BI` | Trigger | `triggers/001_key_assignment.sql` | 52-60 | Assigns invoice keys and normalizes invoice numbers. | Medium | `PKG_BILLING` already supplies an explicit sequence value, so conversion must avoid a second allocation. |
| `TRG_ORDER_LINES_AI` | Trigger | `triggers/002_derived_values.sql` | 1-18 | Recalculates order subtotal and total after selected order-line changes. | High | It queries the mutating row table in an Oracle row trigger and conflicts with the package's fuller tax and discount calculation. |
| `TRG_PAYMENTS_AI` | Trigger | `triggers/002_derived_values.sql` | 20-29 | Marks a non-paid invoice partial after a payment insert while preserving `VOID`. | High | `PKG_BILLING.APPLY_PAYMENT` immediately applies a different status rule, including overwriting a void invoice. |
| `TRG_AUDIT_LOG_BI` | Trigger | `triggers/002_derived_values.sql` | 31-42 | Assigns missing audit keys and event times. | Medium | It overlaps explicit sequence and timestamp values in `PKG_BILLING` and must remain safe for other writers. |
| `PKG_ORDER_MGMT` | Package specification | `packages/pkg_order_mgmt.pks` | 1-37 | Declares six order-management procedures and public session state. | High | PostgreSQL has no package namespace or package-session variable model, and callers depend on Oracle procedure and ref-cursor APIs. |
| `PKG_ORDER_MGMT` | Package body | `packages/pkg_order_mgmt.pkb` | 1-215 | Implements order creation, lines, totals, paging, temporary loads, and summaries. | High | It combines state, savepoints, dynamic SQL, bulk operations, Oracle SQL syntax, output calls, and trigger-coupled writes. |
| `PKG_ORDER_MGMT.CREATE_ORDER` | Public procedure | `packages/pkg_order_mgmt.pkb` | 5-52 | Creates an order, sets status from requester, records package state, and returns the key. | High | Empty strings, package state, savepoint handling, `DUAL`, dynamic SQL, trigger key assignment, and Oracle errors all affect behavior. |
| `PKG_ORDER_MGMT.ADD_ORDER_LINE` | Public procedure | `packages/pkg_order_mgmt.pkb` | 54-87 | Appends a numbered order line and refreshes order totals. | High | `MAX + 1` is concurrency-sensitive and the insert fires a problematic total trigger before the package recalculates totals. |
| `PKG_ORDER_MGMT.REFRESH_ORDER_TOTAL` | Public procedure | `packages/pkg_order_mgmt.pkb` | 89-110 | Calculates subtotal, discount, fixed-rate tax, and total for one order. | Medium | Numeric rounding and tax ownership are clear in code, but they conflict with trigger and invoice calculations. |
| `PKG_ORDER_MGMT.LIST_CUSTOMER_ORDERS` | Public procedure | `packages/pkg_order_mgmt.pkb` | 112-144 | Returns a paged ref cursor of a customer's newest orders. | High | `ROWNUM`, optimizer hints, nested ordering, ref cursors, defaults, and invalid page inputs need an explicit target API. |
| `PKG_ORDER_MGMT.LOAD_ORDER_TOTALS` | Public procedure | `packages/pkg_order_mgmt.pkb` | 146-174 | Bulk-loads customer order totals into a commit-cleared global temporary table. | High | GTT session scope, savepoints, `BULK COLLECT`, `FORALL`, empty collections, and connection pooling all affect results. |
| `PKG_ORDER_MGMT.SUMMARIZE_ORDER` | Public procedure | `packages/pkg_order_mgmt.pkb` | 176-212 | Writes order-line and optional-invoice details to `DBMS_OUTPUT`. | High | Reverse-loop bounds, legacy outer joins, output transport, and its no-lines marker behavior differ in PostgreSQL. |
| `PKG_BILLING` | Package specification | `packages/pkg_billing.pks` | 1-23 | Declares four billing and audit procedures. | High | The interface relies on Oracle procedures, package naming, typed anchors, and transaction behavior. |
| `PKG_BILLING` | Package body | `packages/pkg_billing.pkb` | 1-191 | Implements independent audit logging, invoice issuance, payment application, and total rebuilding. | High | It uses autonomous transactions, package state, LOB APIs, sequence state, dynamic bulk SQL, and overlapping triggers. |
| `PKG_BILLING.WRITE_BILLING_LOG` | Public procedure | `packages/pkg_billing.pkb` | 5-35 | Writes and commits an invoice audit event independently, suppressing all errors. | High | PostgreSQL functions cannot start an Oracle-style autonomous transaction on the same connection. |
| `PKG_BILLING.ISSUE_INVOICE` | Public procedure | `packages/pkg_billing.pkb` | 37-94 | Creates one issued invoice, a temporary delivery-note CLOB, and an audit event. | High | `NEXTVAL` and `CURRVAL`, temporary LOBs, date arithmetic, package state, and autonomous logging need redesign. |
| `PKG_BILLING.APPLY_PAYMENT` | Public procedure | `packages/pkg_billing.pkb` | 96-153 | Locks an invoice, inserts a payment, sets invoice status, and writes an audit event. | High | Empty strings, lock and transaction scope, trigger conflicts, void handling, overpayment behavior, and autonomous logs must be resolved. |
| `PKG_BILLING.REBUILD_INVOICE_TOTALS` | Public procedure | `packages/pkg_billing.pkb` | 155-188 | Bulk-reads invoice lines, recomputes line tax, and updates invoice totals. | High | Dynamic SQL, `BULK COLLECT`, `FORALL`, package state, empty collections, and tax-total meaning require a set-based rewrite. |
| `PKG_CUSTOMER_HIER` | Package specification | `packages/pkg_customer_hier.pks` | 1-19 | Declares hierarchy reporting, ancestor, unordered-customer, and descendant-count APIs. | Medium | The API can be separated into PostgreSQL functions, but ref cursors and return types need caller decisions. |
| `PKG_CUSTOMER_HIER` | Package body | `packages/pkg_customer_hier.pkb` | 1-72 | Implements hierarchy traversal, set subtraction, output, and descendant counting. | High | `CONNECT BY`, `LEVEL`, sibling ordering, `MINUS`, `SYSDATE`, and `DBMS_OUTPUT` need behavior-preserving rewrites. |
| `PKG_CUSTOMER_HIER.PRINT_TREE` | Public procedure | `packages/pkg_customer_hier.pkb` | 3-23 | Traverses a customer subtree and writes indented nodes to `DBMS_OUTPUT`. | High | Recursive query order, cycle behavior, path formatting, and output transport need explicit equivalents. |
| `PKG_CUSTOMER_HIER.LIST_ANCESTORS` | Public procedure | `packages/pkg_customer_hier.pkb` | 25-36 | Returns the selected customer and its ancestors through a ref cursor. | High | Upward `CONNECT BY` direction, depth numbering, cycle behavior, and ref-cursor delivery must be preserved. |
| `PKG_CUSTOMER_HIER.FIND_UNORDERED_CUSTOMERS` | Public procedure | `packages/pkg_customer_hier.pkb` | 38-51 | Returns active customers with no order in the last 90 days. | Medium | `MINUS` maps to `EXCEPT`, but `SYSDATE - 90` uses timestamp precision and the result API is a ref cursor. |
| `PKG_CUSTOMER_HIER.DESCENDANT_COUNT` | Public function | `packages/pkg_customer_hier.pkb` | 53-69 | Counts the root customer plus all reachable descendants. | High | Recursive traversal and cycle handling need a rewrite, and the function name may not match its root-inclusive behavior. |

## Complexity distribution

The distribution below counts all 66 inventory entries, including the 14 public routines:

| Complexity | Count |
|---|---:|
| Low | 18 |
| Medium | 24 |
| High | 24 |

The grade is conversion complexity, not object size. A one-line bitmap index is High because PostgreSQL has no equivalent object, while several longer B-tree definitions are Low.
