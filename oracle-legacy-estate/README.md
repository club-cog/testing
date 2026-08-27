# Synthetic Oracle legacy estate

This is synthetic Oracle 19c-style code authored as a migration demo fixture. It contains no customer data and is not production code.

The estate models a small, invented retail-orders and billing system. Every name,
identifier, value, and comment in this directory was created for migration
demonstrations. It is intentionally uneven, incomplete, and Oracle-specific so
that a migration session has real seams to inspect.

## Contents

- `ddl/`: tables, sequences, indexes, a synonym, a materialized view, and a global temporary table
- `packages/`: three PL/SQL packages with specifications and bodies
- `triggers/`: row-level key assignment, derived totals, and audit behavior
- `views/`: reporting views, including an old-style outer join and a `ROWNUM` view
- `app/`: small application-side DAO examples and raw SQL references
- `docs/estate-notes.md`: deliberately incomplete inherited notes

## Intended use

Treat this as an Oracle 19c source estate only. It is not expected to run
without an Oracle database and suitable local objects. Connection values in the
application examples are obvious placeholders. A migration exercise can use
this fixture to demonstrate schema translation, PL/SQL conversion, and
application-side reference updates.

The awkward constructs are deliberate. Examples include Oracle empty-string
semantics, `DATE` columns used as timestamps, IOT storage, legacy join syntax,
package state, dynamic SQL, and trigger-maintained values.
