# Data dictionary

Meanings marked "Inferred" are based on names and usage because no authoritative domain glossary or data was supplied. Nullability reflects Oracle behavior, including primary-key non-null enforcement and the fact that a default does not make a column non-null.

## `CUSTOMERS`

Source: `ddl/001_tables.sql:4-24`

| Column | Oracle type | Nullable | Keys and defaults | Inferred meaning and rules |
|---|---|---|---|---|
| `CUSTOMER_ID` | `NUMBER` | No | Primary key; `SEQ_CUSTOMERS` is assigned by `TRG_CUSTOMERS_BI` when null. | Surrogate customer identifier. Explicit identifiers are accepted on insert. |
| `CUSTOMER_CODE` | `VARCHAR2(24 CHAR)` | No | Unique | External or display code. `TRG_CUSTOMERS_BI` uppercases and trims it on insert at `triggers/001_key_assignment.sql:11`. Updates are not normalized by the trigger. |
| `DISPLAY_NAME` | `VARCHAR2(160 BYTE)` | No | None | Human-readable customer name. The byte limit can allow fewer than 160 multibyte characters. |
| `STATUS` | `VARCHAR2(1 BYTE)` | Yes | Default `A`; check permits `A`, `I`, or `H`. | Customer state, likely active, inactive, or held. The letter meanings are inferred. `TRG_CUSTOMERS_BI` changes null to `A` on insert. |
| `PREFERRED_CHANNEL` | `VARCHAR2(12 CHAR)` | Yes | `DEFAULT ''`, which is null in Oracle; check is `<> ''`. | Optional contact channel. The default is null and the check does not reject null, so no nonblank value is actually required. |
| `CREDIT_LIMIT` | `NUMBER(12,2)` | Yes | Check permits null or values at least zero. | Optional customer credit ceiling. Currency is not stored with this value. |
| `JOINED_ON` | `DATE` | Yes | Default `SYSDATE` | Customer join timestamp, despite the `_ON` name. |
| `LAST_CONTACTED_ON` | `DATE` | Yes | None | Most recent contact timestamp. No included code maintains it. |
| `PARENT_CUSTOMER_ID` | `NUMBER` | Yes | Self-referencing foreign key to `CUSTOMERS.CUSTOMER_ID`. | Parent in the customer hierarchy. No check prevents self-parenting or longer cycles. |
| `PROFILE_NOTE` | `CLOB` | Yes | None | Free-form customer profile text. |
| `AVATAR_BLOB` | `BLOB` | Yes | None | Binary customer image or avatar. The exact format is unknown. |
| `EXTERNAL_REF` | `RAW(16)` | Yes | None | Opaque 16-byte external reference. It may be a UUID, but the source does not prove that. |

Implicit table rules:

- Hierarchy routines treat the selected root as level 1 and include it in `DESCENDANT_COUNT` at `packages/pkg_customer_hier.pkb:53-69`.
- `FIND_UNORDERED_CUSTOMERS` only considers status `A` and a rolling 90-day order window at `packages/pkg_customer_hier.pkb:38-51`.
- Hierarchy cycles are possible in the DDL and would cause the included `CONNECT BY` queries to error because they do not use `NOCYCLE`.

## `ADDRESSES`

Source: `ddl/001_tables.sql:30-47`

| Column | Oracle type | Nullable | Keys and defaults | Inferred meaning and rules |
|---|---|---|---|---|
| `ADDRESS_ID` | `NUMBER` | No | Primary key; `SEQ_ADDRESSES` is assigned by `TRG_ADDRESSES_BI` when null. | Surrogate address identifier. Explicit identifiers are accepted. |
| `CUSTOMER_ID` | `NUMBER` | No | Foreign key to `CUSTOMERS.CUSTOMER_ID`. | Owner of the address. |
| `ADDRESS_KIND` | `VARCHAR2(10 CHAR)` | Yes | Default `SHIP`; check permits `BILL`, `SHIP`, or `OTHER`. | Address role. Null is still allowed because the check does not reject it. |
| `LINE_ONE` | `VARCHAR2(120 BYTE)` | No | None | Required first address line. |
| `LINE_TWO` | `VARCHAR2(120 BYTE)` | Yes | None | Optional second address line. |
| `CITY_NAME` | `VARCHAR2(80 CHAR)` | No | None | City or locality. |
| `REGION_CODE` | `VARCHAR2(12 BYTE)` | Yes | None | State, province, or other region code. |
| `POSTAL_CODE` | `VARCHAR2(16 CHAR)` | Yes | None | Postal code. No format rule is enforced. |
| `COUNTRY_CODE` | `VARCHAR2(2 BYTE)` | Yes | Default `ZZ` | Two-byte country marker. `TRG_ADDRESSES_BI` uppercases it and converts null to `ZZ` on insert. The source does not prove ISO 3166 use. |
| `VALIDATED_FLAG` | `VARCHAR2(1 BYTE)` | Yes | `DEFAULT ''`, which is null in Oracle; check is `<> ''`. | Intended validation marker. The current default and check leave it null, and no allowed values are defined. |
| `CREATED_AT` | `DATE` | Yes | Default `SYSDATE` | Address creation timestamp. |

Implicit table rules:

- Orders may reference separate bill and ship addresses, but the foreign keys do not require those addresses to belong to the same customer as the order.
- Insert normalization is not repeated on update.

## `PRODUCTS`

Source: `ddl/001_tables.sql:49-65`

| Column | Oracle type | Nullable | Keys and defaults | Inferred meaning and rules |
|---|---|---|---|---|
| `PRODUCT_ID` | `NUMBER` | No | Primary key; `SEQ_PRODUCTS` is assigned by `TRG_PRODUCTS_BI` when null. | Surrogate product identifier. |
| `SKU` | `VARCHAR2(30 BYTE)` | No | Unique | Stock-keeping code. The insert trigger trims and uppercases it at `triggers/001_key_assignment.sql:34`. |
| `PRODUCT_NAME` | `VARCHAR2(140 CHAR)` | No | None | Product display name. |
| `PRODUCT_GROUP` | `VARCHAR2(40 CHAR)` | Yes | Indexed with `ACTIVE_FLAG`. | Optional grouping or category. No reference table enforces values. |
| `ACTIVE_FLAG` | `VARCHAR2(1 BYTE)` | Yes | Default `Y`; check permits `Y` or `N`. | Whether the product can be used. Null remains allowed. |
| `BASE_PRICE` | `NUMBER(10,2)` | No | Check requires at least zero. | Base unit price, with no currency column on the product. |
| `WEIGHT_KG` | `NUMBER` | Yes | None | Product weight in kilograms. Precision, scale, and nonnegative rules are absent. |
| `DESCRIPTION` | `CLOB` | Yes | None | Long product description. |
| `IMAGE_BLOB` | `BLOB` | Yes | None | Product image bytes. Format and size are unknown. |
| `CREATED_ON` | `DATE` | Yes | Default `SYSDATE` | Product creation timestamp. |
| `RETIRED_ON` | `DATE` | Yes | None | Product retirement timestamp. No check requires it to follow `CREATED_ON`. |

## `PRICE_TIERS`

Source: `ddl/001_tables.sql:67-82`

| Column | Oracle type | Nullable | Keys and defaults | Inferred meaning and rules |
|---|---|---|---|---|
| `TIER_ID` | `NUMBER` | No | Primary key; `SEQ_PRICE_TIERS` exists but no included assignment path uses it. | Surrogate price-tier identifier. Key generation is incomplete in the supplied estate. |
| `PRODUCT_ID` | `NUMBER` | No | Foreign key to `PRODUCTS.PRODUCT_ID`; unique with `TIER_CODE`. | Product receiving the tier price. |
| `TIER_CODE` | `VARCHAR2(12 CHAR)` | No | Unique with `PRODUCT_ID`. | Product-local tier name or code. |
| `MINIMUM_QUANTITY` | `NUMBER` | Yes | Default `1`; check requires greater than zero. | Quantity threshold at which the tier applies. Fractions are not prohibited by the DDL. |
| `UNIT_PRICE` | `NUMBER(10,2)` | No | None | Price per unit for the tier. Unlike `PRODUCTS.BASE_PRICE`, it has no nonnegative check. |
| `VALID_FROM` | `DATE` | Yes | Default `SYSDATE` | Start timestamp for tier validity. |
| `VALID_TO` | `DATE` | Yes | Check spells null or at least `VALID_FROM`; a null `VALID_FROM` makes the comparison unknown and therefore pass. | Optional end timestamp. Overlapping tiers are not prohibited. |
| `TIER_NOTE` | `VARCHAR2(240 BYTE)` | Yes | None | Free-form short note. |

No included package or application query applies price tiers, so precedence among eligible tiers is unknown.

## `ORDERS`

Source: `ddl/001_tables.sql:84-112`

| Column | Oracle type | Nullable | Keys and defaults | Inferred meaning and rules |
|---|---|---|---|---|
| `ORDER_ID` | `NUMBER` | No | Primary key; `SEQ_ORDERS` is assigned by `TRG_ORDERS_BI` when null. | Surrogate order identifier. The application also advances the sequence to propose an order number at `app/raw_queries.sql:34-35`. |
| `ORDER_NUMBER` | `VARCHAR2(28 BYTE)` | No | Unique | Business-facing order number. The insert trigger trims and uppercases it. `CREATE_ORDER` converts duplicate-key failures to application error `-20901`. |
| `CUSTOMER_ID` | `NUMBER` | No | Foreign key to `CUSTOMERS.CUSTOMER_ID`. | Customer placing the order. |
| `BILL_ADDRESS_ID` | `NUMBER` | Yes | Foreign key to `ADDRESSES.ADDRESS_ID`. | Billing address. Ownership by `CUSTOMER_ID` is not enforced. |
| `SHIP_ADDRESS_ID` | `NUMBER` | Yes | Foreign key to `ADDRESSES.ADDRESS_ID`. | Shipping address. Ownership by `CUSTOMER_ID` is not enforced. |
| `ORDER_STATUS` | `VARCHAR2(16 CHAR)` | No | Default `OPEN`; check permits `OPEN`, `HELD`, `READY`, `CLOSED`, or `VOID`. | Order lifecycle state. `CREATE_ORDER` chooses `OPEN` only for requester `BATCH` or null, otherwise `HELD`. |
| `ORDERED_AT` | `DATE` | Yes | Default `SYSDATE` | Order timestamp. Paging and recent-order queries sort by it. |
| `REQUESTED_BY` | `VARCHAR2(80 BYTE)` | Yes | None | Requesting user, integration, or batch label. `CREATE_ORDER` stores `BATCH` when the input is null or empty under Oracle semantics. |
| `CURRENCY_CODE` | `VARCHAR2(3 BYTE)` | Yes | Default `ZZ` | Currency marker for order amounts. The source does not prove ISO 4217 use, and no package validates it. |
| `SUBTOTAL_AMOUNT` | `NUMBER(14,2)` | Yes | Default `0` | Sum of line `EXTENDED_AMOUNT`. The package and trigger both maintain it. |
| `DISCOUNT_AMOUNT` | `NUMBER(14,2)` | Yes | Default `0` | Sum of `EXTENDED_AMOUNT * DISCOUNT_RATE / 100` in `REFRESH_ORDER_TOTAL`. |
| `TAX_AMOUNT` | `NUMBER(14,2)` | Yes | Default `0` | Fixed 8.25 percent tax on subtotal less discount in `REFRESH_ORDER_TOTAL`. |
| `TOTAL_AMOUNT` | `NUMBER(14,2)` | Yes | Default `0`; check requires at least zero. | Package rule is subtotal minus discount plus tax. `TRG_ORDER_LINES_AI` instead sets it to raw line sum. The order insert trigger converts null to zero. |
| `NOTE_TEXT` | `CLOB` | Yes | None | Long order note. |
| `SOURCE_TOKEN` | `RAW(16)` | Yes | None | Opaque 16-byte source or idempotency token. No uniqueness rule enforces idempotency. |

Implicit table rules:

- `CREATE_ORDER` uses a savepoint and leaves commit control to the caller at `packages/pkg_order_mgmt.pkb:15-51`.
- Page order is newest `ORDERED_AT` first, but ties have no stable secondary key.
- `V_RECENT_ORDERS` exposes the newest 50 rows.
- `CURRENT_ORDERS` is only a synonym. It does not filter out closed or void orders.

## `ORDER_LINES`

Source: `ddl/001_tables.sql:116-135`

| Column | Oracle type | Nullable | Keys and defaults | Inferred meaning and rules |
|---|---|---|---|---|
| `ORDER_ID` | `NUMBER` | No | Primary key with `LINE_NUMBER`; foreign key to `ORDERS.ORDER_ID`. | Parent order. |
| `LINE_NUMBER` | `NUMBER` | No | Primary key with `ORDER_ID`. | Order-local line position. `ADD_ORDER_LINE` assigns `MAX + 1`, which can race under concurrent inserts. |
| `PRODUCT_ID` | `NUMBER` | No | Foreign key to `PRODUCTS.PRODUCT_ID`; separately indexed. | Product sold on the line. Product active state is not checked. |
| `QUANTITY` | `NUMBER` | No | Default `1`; check requires greater than zero. | Ordered quantity. Fractional quantities are not prohibited. |
| `UNIT_PRICE` | `NUMBER(10,2)` | No | None | Captured per-unit price. It is supplied by the caller; the package does not read `PRODUCTS` or `PRICE_TIERS`. |
| `DISCOUNT_RATE` | `NUMBER(5,2)` | Yes | Default `0`; check requires 0 through 100. | Percentage discount. `ADD_ORDER_LINE` always inserts zero, but other writers can set it. |
| `EXTENDED_AMOUNT` | `NUMBER(14,2)` | Yes | None | `ADD_ORDER_LINE` sets quantity times unit price. No trigger recomputes it after quantity, unit price, or discount updates. |
| `LINE_NOTE` | `VARCHAR2(240 CHAR)` | Yes | None | Optional short line note. |

Implicit table rules:

- The table is an Oracle IOT keyed by `(ORDER_ID, LINE_NUMBER)`, with `QUANTITY` in the primary area and later columns eligible for overflow.
- `TRG_ORDER_LINES_AI` attempts to recalculate parent totals after inserts and selected updates, but its query of the mutating table is expected to fail in Oracle row-trigger execution.
- Deleting a line does not fire `TRG_ORDER_LINES_AI`, so direct deletes leave order totals stale.
- Updating `PRODUCT_ID`, `EXTENDED_AMOUNT`, or deleting a line also does not trigger the declared total recalculation.

## `INVOICES`

Source: `ddl/001_tables.sql:137-156`

| Column | Oracle type | Nullable | Keys and defaults | Inferred meaning and rules |
|---|---|---|---|---|
| `INVOICE_ID` | `NUMBER` | No | Primary key; `SEQ_INVOICES` can be assigned by trigger or package. | Surrogate invoice identifier. `ISSUE_INVOICE` advances the sequence, uses `CURRVAL`, and supplies the key explicitly. |
| `INVOICE_NUMBER` | `VARCHAR2(28 BYTE)` | No | Unique | Business invoice number. `ISSUE_INVOICE` forms `INV-` plus the sequence value; the trigger uppercases and trims it. |
| `ORDER_ID` | `NUMBER` | No | Unique; foreign key to `ORDERS.ORDER_ID`. | Enforces at most one invoice per order. |
| `ISSUED_ON` | `DATE` | Yes | Default `SYSDATE` | Invoice issue timestamp. |
| `DUE_ON` | `DATE` | Yes | None | Payment due timestamp. `ISSUE_INVOICE` sets it exactly 30 days after issue time. |
| `INVOICE_STATUS` | `VARCHAR2(14 CHAR)` | Yes | Default `DRAFT`; check permits `DRAFT`, `ISSUED`, `PARTIAL`, `PAID`, or `VOID`. | Invoice lifecycle state. Payment trigger and package contain conflicting rules for `VOID`. |
| `INVOICE_TOTAL` | `NUMBER(14,2)` | Yes | Default `0` | `ISSUE_INVOICE` copies `ORDERS.TOTAL_AMOUNT`; `REBUILD_INVOICE_TOTALS` replaces it with the sum of invoice-line amounts. |
| `TAX_TOTAL` | `NUMBER(14,2)` | Yes | Default `0` | `ISSUE_INVOICE` sets 8.25 percent of copied order total; rebuild sets 8.25 percent of invoice-line total. Whether `INVOICE_TOTAL` is tax-inclusive is ambiguous. |
| `RENDERED_PDF` | `BLOB` | Yes | None | Rendered invoice document bytes. No included code writes it. |
| `DELIVERY_NOTE` | `CLOB` | Yes | None | Long delivery or generation note. `ISSUE_INVOICE` writes a fixed legacy-batch message. |

Implicit table rules:

- The included package issues invoices directly in status `ISSUED`, bypassing the default `DRAFT`.
- `APPLY_PAYMENT` locks the invoice row before totaling captured payments.
- The schema does not check nonnegative totals or require `DUE_ON >= ISSUED_ON`.

## `INVOICE_LINES`

Source: `ddl/001_tables.sql:158-170`

| Column | Oracle type | Nullable | Keys and defaults | Inferred meaning and rules |
|---|---|---|---|---|
| `INVOICE_LINE_ID` | `NUMBER` | No | Primary key; `SEQ_INVOICE_LINES` exists but no included assignment path uses it. | Surrogate invoice-line identifier. |
| `INVOICE_ID` | `NUMBER` | No | Foreign key to `INVOICES.INVOICE_ID`; unique with `ORDER_LINE_NUMBER` through an explicit index. | Parent invoice. |
| `ORDER_LINE_NUMBER` | `NUMBER` | No | Unique with `INVOICE_ID`. | Refers by name to an order line number, but no foreign key ties it to `ORDER_LINES` or the invoice's order. |
| `LINE_TEXT` | `VARCHAR2(180 CHAR)` | Yes | None | Invoice display text. |
| `QUANTITY` | `NUMBER(9,0)` | Yes | Check requires greater than zero. | Billed quantity. Null is allowed despite the check. |
| `LINE_AMOUNT` | `NUMBER(14,2)` | Yes | None | Amount before the separately stored tax calculation. |
| `TAX_AMOUNT` | `NUMBER(14,2)` | Yes | None | `REBUILD_INVOICE_TOTALS` sets 8.25 percent of `LINE_AMOUNT`, rounded to two decimals. |

No included routine creates invoice lines. `ISSUE_INVOICE` creates only the invoice header, so the source does not show when or how lines are populated.

## `PAYMENTS`

Source: `ddl/001_tables.sql:172-188`

| Column | Oracle type | Nullable | Keys and defaults | Inferred meaning and rules |
|---|---|---|---|---|
| `PAYMENT_ID` | `NUMBER` | No | Primary key; `SEQ_PAYMENTS` is used by `APPLY_PAYMENT`. | Surrogate payment identifier. |
| `INVOICE_ID` | `NUMBER` | No | Foreign key to `INVOICES.INVOICE_ID`. | Invoice receiving the payment. |
| `PAID_ON` | `DATE` | Yes | Default `SYSDATE` | Payment timestamp. |
| `PAYMENT_METHOD` | `VARCHAR2(14 BYTE)` | Yes | None | Payment method text. The package substitutes `UNKNOWN` for null or Oracle empty string. No controlled values exist. |
| `PAYMENT_STATUS` | `VARCHAR2(12 CHAR)` | Yes | Default `CAPTURED`; check permits `CAPTURED`, `PENDING`, or `REVERSED`. | Settlement state. `APPLY_PAYMENT` inserts `PENDING` only when the invoice was `VOID`; otherwise it inserts `CAPTURED`. |
| `AMOUNT_PAID` | `NUMBER(14,2)` | No | Check requires greater than zero. | Payment amount. Currency is inherited by implication from the order, not stored. |
| `CONFIRMATION_CODE` | `RAW(16)` | Yes | None | Opaque 16-byte gateway confirmation. No included code writes it. |
| `GATEWAY_NOTE` | `CLOB` | Yes | None | Long gateway response or note. No included code writes it. |

Implicit table rules:

- Invoice paid total includes only rows with status `CAPTURED` at `packages/pkg_billing.pkb:111-115`.
- `REVERSED` rows remain stored and are excluded from paid total.
- The package does not reject overpayment. Any captured total at least equal to invoice total sets the invoice `PAID`.
- The package does not reject null amount directly, but the table's not-null constraint does.

## `AUDIT_LOG`

Source: `ddl/001_tables.sql:190-200`

| Column | Oracle type | Nullable | Keys and defaults | Inferred meaning and rules |
|---|---|---|---|---|
| `AUDIT_ID` | `NUMBER` | No | Primary key; trigger assigns `SEQ_AUDIT_LOG` when null. | Surrogate audit event identifier. Billing code also supplies the same sequence explicitly. |
| `EVENT_TIME` | `DATE` | Yes | Default `SYSDATE`; trigger also supplies `SYSDATE` when null. | Event timestamp. |
| `ENTITY_NAME` | `VARCHAR2(40 BYTE)` | No | None | Entity category. Included billing code always writes `INVOICE`. |
| `ENTITY_ID` | `NUMBER` | Yes | None | Identifier of the affected entity. No foreign key is possible under the generic design. |
| `ACTION_CODE` | `VARCHAR2(20 CHAR)` | No | None | Event action. Included values are `ISSUED` and `PAYMENT`. |
| `ACTOR_NAME` | `VARCHAR2(80 BYTE)` | Yes | None | Oracle session user or `BATCH` fallback in billing code. |
| `PAYLOAD` | `CLOB` | Yes | None | Event detail. Included payloads contain a package run label or payment amount and method. |
| `EVENT_FINGERPRINT` | `RAW(16)` | Yes | None | Optional opaque event fingerprint. No included code writes or checks it. |

Implicit table rules:

- `WRITE_BILLING_LOG` commits rows independently of the business transaction.
- Any audit failure is rolled back and suppressed, so the absence of an event does not prove the business operation did not occur.

## `GTT_ORDER_TOTALS`

Source: `ddl/001_tables.sql:202-207`

| Column | Oracle type | Nullable | Keys and defaults | Inferred meaning and rules |
|---|---|---|---|---|
| `ORDER_ID` | `NUMBER` | Yes | None | Order represented by the work row. No primary or foreign key is declared. |
| `LINE_COUNT` | `NUMBER` | Yes | None | Count of order lines when `LOAD_ORDER_TOTALS` ran. |
| `CALCULATED_TOTAL` | `NUMBER(14,2)` | Yes | None | Despite the name, `LOAD_ORDER_TOTALS` copies `ORDERS.TOTAL_AMOUNT` rather than recalculating it from lines. |
| `LOADED_AT` | `DATE` | Yes | Default `SYSDATE` | Work-row load timestamp. |

Implicit table rules:

- Rows are private to the Oracle session and deleted on every commit.
- `LOAD_ORDER_TOTALS` clears all current-session rows before loading one customer's orders.
- The procedure inserts one row for each order returned by its bulk query. It counts lines independently but trusts the stored order total.
- Application commits or pool checkout boundaries can erase or hide rows before a later consumer reads them.
