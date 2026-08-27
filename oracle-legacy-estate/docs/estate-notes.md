# Inherited estate notes

This note is intentionally incomplete. It is synthetic working material for a
migration demo, not a production runbook.

- Current source database is believed to be Oracle 19c, but the exact patch level
  is not recorded.
- `orders` and `invoices` are the important screens. Someone should confirm
  whether the materialized view is refreshed by the nightly job or manually.
- The `preferred_channel` and `validated_flag` columns have surprising behavior
  when the old loader sends an empty string.
- Billing appears to call `PKG_BILLING` from a scheduler, but the scheduler
  definition was not included in the handoff.
- There may be reports outside this schema that refer to the `CURRENT_ORDERS`
  synonym.
- No reliable row counts, grants, database links, or export files were included.
- The application uses a legacy Oracle driver. Search all deployment scripts for
  another connection factory before changing the DAO.
- Do not assume `DATE` means date-only. Several screens compare it to a time
  window.
