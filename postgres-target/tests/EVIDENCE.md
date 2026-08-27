# Executed test evidence

Real output from this machine, pasted unedited. The two count queries in
sections 3 and 4 are `postgres-target/scripts/counts.sql` and
`postgres-target/scripts/rows.sql`.

Environment:

- PostgreSQL 16.15 in Docker (`postgres:16`), listening on 127.0.0.1:55432
- Python 3.10.12, psycopg 3.3.4 (binary), pytest 9.1.1
- Database `oracle_migration_demo`, synthetic seed data only

## 1. Server version

```
$ docker exec pgdemo psql -U demo -d oracle_migration_demo -c "select version()"
                                                       version                                                        
----------------------------------------------------------------------------------------------------------------------
 PostgreSQL 16.15 (Debian 16.15-1.pgdg13+2) on x86_64-pc-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit
(1 row)
```

## 2. Apply migrations, functions and seed

```
$ .venv-pg/bin/python postgres-target/scripts/rebuild.py
applied postgres-target/migrations/V001__schemas_and_helpers.sql
applied postgres-target/migrations/V002__tables.sql
applied postgres-target/migrations/V003__sequences.sql
applied postgres-target/migrations/V004__indexes.sql
applied postgres-target/migrations/V005__views.sql
applied postgres-target/migrations/V006__oracle_only_objects.sql
applied postgres-target/migrations/V007__triggers.sql
applied postgres-target/functions/pkg_billing.sql
applied postgres-target/functions/pkg_customer_hier.sql
applied postgres-target/functions/pkg_order_mgmt.sql
applied postgres-target/seed/S001__reference_data.sql
applied postgres-target/seed/S002__transactions.sql
applied postgres-target/seed/S003__sequence_alignment.sql
rebuild complete: 13 files applied to oracle_migration_demo
```

## 3. Converted object counts in the target database

```
$ psql -U demo -d oracle_migration_demo -f counts.sql
    object_kind     | n  
--------------------+----
 indexes            | 31
 materialized views |  1
 package functions  | 19
 retail functions   | 14
 sequences          |  9
 tables             | 11
 triggers           | 10
 views              |  5
(8 rows)
```

`retail functions` covers `sysdate()`, the empty string helper, the temp table
helper, the materialized view refresh helper and the 10 trigger functions.
`package functions` covers the three converted packages, including the package
state accessors.

## 4. Seeded row counts

```
$ psql -U demo -d oracle_migration_demo -f rows.sql
  table_name   | rows 
---------------+------
 addresses     |    4
 audit_log     |    1
 customers     |   10
 invoice_lines |    3
 invoices      |    3
 order_lines   |    4
 orders        |   12
 payments      |    2
 price_tiers   |    3
 products      |    3
(10 rows)
```

## 5. Full test run

```
$ .venv-pg/bin/python -m pytest postgres-target/tests -v
============================= test session starts ==============================
platform linux -- Python 3.10.12, pytest-9.1.1, pluggy-1.6.0 -- /home/ubuntu/repos/testing/.venv-pg/bin/python
cachedir: .pytest_cache
rootdir: /home/ubuntu/repos/testing
collecting ... collected 122 items

postgres-target/tests/test_app_dao.py::test_connection_wrapper_reads_the_environment PASSED [  0%]
postgres-target/tests/test_app_dao.py::test_order_dao_create_and_add_line PASSED [  1%]
postgres-target/tests/test_app_dao.py::test_order_dao_pagination_matches_the_function PASSED [  2%]
postgres-target/tests/test_app_dao.py::test_order_dao_summary_query_replaces_the_plus_join PASSED [  3%]
postgres-target/tests/test_app_dao.py::test_order_dao_reads_the_gtt_before_commit PASSED [  4%]
postgres-target/tests/test_app_dao.py::test_order_dao_exposes_package_state PASSED [  4%]
postgres-target/tests/test_app_dao.py::test_order_dao_summarize PASSED   [  5%]
postgres-target/tests/test_app_dao.py::test_billing_dao_issue_and_pay PASSED [  6%]
postgres-target/tests/test_app_dao.py::test_billing_dao_log_helper PASSED [  7%]
postgres-target/tests/test_app_dao.py::test_hierarchy_dao PASSED         [  8%]
postgres-target/tests/test_app_dao.py::test_worker_runs_the_whole_flow PASSED [  9%]
postgres-target/tests/test_app_dao.py::test_worker_fetch_page PASSED     [  9%]
postgres-target/tests/test_pkg_billing.py::test_issue_invoice_creates_issued_invoice PASSED [ 10%]
postgres-target/tests/test_pkg_billing.py::test_issue_invoice_carries_order_total_and_tax PASSED [ 11%]
postgres-target/tests/test_pkg_billing.py::test_issue_invoice_writes_audit_row_and_sets_run_label PASSED [ 12%]
postgres-target/tests/test_pkg_billing.py::test_billing_log_rolls_back_with_caller_unlike_autonomous_transaction PASSED [ 13%]
postgres-target/tests/test_pkg_billing.py::test_write_billing_log_swallows_its_own_failure PASSED [ 13%]
postgres-target/tests/test_pkg_billing.py::test_write_billing_log_autonomous_degrades_without_dblink PASSED [ 14%]
postgres-target/tests/test_pkg_billing.py::test_issue_invoice_missing_order_is_mapped_error PASSED [ 15%]
postgres-target/tests/test_pkg_billing.py::test_issue_invoice_duplicate_order_is_mapped_error PASSED [ 16%]
postgres-target/tests/test_pkg_billing.py::test_apply_payment_partial_then_paid PASSED [ 17%]
postgres-target/tests/test_pkg_billing.py::test_apply_payment_defaults_unknown_method PASSED [ 18%]
postgres-target/tests/test_pkg_billing.py::test_apply_payment_against_void_invoice_keeps_oracle_behaviour PASSED [ 18%]
postgres-target/tests/test_pkg_billing.py::test_apply_payment_zero_value_invoice_is_paid_immediately PASSED [ 19%]
postgres-target/tests/test_pkg_billing.py::test_apply_payment_missing_invoice_is_mapped_error PASSED [ 20%]
postgres-target/tests/test_pkg_billing.py::test_apply_payment_writes_audit_row PASSED [ 21%]
postgres-target/tests/test_pkg_billing.py::test_rebuild_invoice_totals_recomputes_from_lines PASSED [ 22%]
postgres-target/tests/test_pkg_billing.py::test_rebuild_invoice_totals_handles_zero_and_null_amounts PASSED [ 22%]
postgres-target/tests/test_pkg_billing.py::test_rebuild_invoice_totals_for_invoice_without_lines PASSED [ 23%]
postgres-target/tests/test_pkg_billing.py::test_run_label_defaults_to_unset_in_a_fresh_session PASSED [ 24%]
postgres-target/tests/test_pkg_customer_hier.py::test_print_tree_walks_depth_first_in_sibling_code_order PASSED [ 25%]
postgres-target/tests/test_pkg_customer_hier.py::test_print_tree_indents_by_level_like_lpad PASSED [ 26%]
postgres-target/tests/test_pkg_customer_hier.py::test_print_tree_from_mid_hierarchy PASSED [ 27%]
postgres-target/tests/test_pkg_customer_hier.py::test_print_tree_leaf_returns_only_itself PASSED [ 27%]
postgres-target/tests/test_pkg_customer_hier.py::test_print_tree_unknown_root_returns_nothing PASSED [ 28%]
postgres-target/tests/test_pkg_customer_hier.py::test_list_ancestors_climbs_five_levels PASSED [ 29%]
postgres-target/tests/test_pkg_customer_hier.py::test_list_ancestors_of_root_is_just_the_root PASSED [ 30%]
postgres-target/tests/test_pkg_customer_hier.py::test_list_ancestors_of_orphan_customer PASSED [ 31%]
postgres-target/tests/test_pkg_customer_hier.py::test_list_ancestors_unknown_customer_returns_nothing PASSED [ 31%]
postgres-target/tests/test_pkg_customer_hier.py::test_find_unordered_customers_excludes_recent_orderers PASSED [ 32%]
postgres-target/tests/test_pkg_customer_hier.py::test_find_unordered_customers_reacts_to_a_new_order PASSED [ 33%]
postgres-target/tests/test_pkg_customer_hier.py::test_find_unordered_customers_ignores_orders_older_than_ninety_days PASSED [ 34%]
postgres-target/tests/test_pkg_customer_hier.py::test_find_unordered_customers_deduplicates_like_minus PASSED [ 35%]
postgres-target/tests/test_pkg_customer_hier.py::test_descendant_count_includes_the_root_row PASSED [ 36%]
postgres-target/tests/test_pkg_customer_hier.py::test_descendant_count_unknown_root_is_zero PASSED [ 36%]
postgres-target/tests/test_pkg_customer_hier.py::test_descendant_count_follows_a_reparent PASSED [ 37%]
postgres-target/tests/test_pkg_customer_hier.py::test_hierarchy_functions_are_schema_qualified PASSED [ 38%]
postgres-target/tests/test_pkg_customer_hier.py::test_deep_hierarchy_level_matches_ancestor_depth PASSED [ 39%]
postgres-target/tests/test_pkg_customer_hier.py::test_one_row_per_customer_in_tree PASSED [ 40%]
postgres-target/tests/test_pkg_order_mgmt.py::test_create_order_defaults_status_open_for_batch PASSED [ 40%]
postgres-target/tests/test_pkg_order_mgmt.py::test_create_order_holds_when_requested_by_present PASSED [ 41%]
postgres-target/tests/test_pkg_order_mgmt.py::test_create_order_normalises_number_through_trigger PASSED [ 42%]
postgres-target/tests/test_pkg_order_mgmt.py::test_package_state_counter_and_last_order_id PASSED [ 43%]
postgres-target/tests/test_pkg_order_mgmt.py::test_package_state_is_transactional_unlike_oracle PASSED [ 44%]
postgres-target/tests/test_pkg_order_mgmt.py::test_duplicate_order_number_raises_mapped_error_and_rolls_back PASSED [ 45%]
postgres-target/tests/test_pkg_order_mgmt.py::test_add_order_line_assigns_next_line_number PASSED [ 45%]
postgres-target/tests/test_pkg_order_mgmt.py::test_add_order_line_updates_totals_with_tax PASSED [ 46%]
postgres-target/tests/test_pkg_order_mgmt.py::test_add_order_line_defaults_null_quantity_to_one PASSED [ 47%]
postgres-target/tests/test_pkg_order_mgmt.py::test_refresh_order_total_applies_line_discount PASSED [ 48%]
postgres-target/tests/test_pkg_order_mgmt.py::test_refresh_order_total_handles_null_extended_amount PASSED [ 49%]
postgres-target/tests/test_pkg_order_mgmt.py::test_refresh_order_total_on_order_without_lines PASSED [ 50%]
postgres-target/tests/test_pkg_order_mgmt.py::test_fractional_quantity_survives_numeric_mapping PASSED [ 50%]
postgres-target/tests/test_pkg_order_mgmt.py::test_list_customer_orders_paginates_like_rownum_version PASSED [ 51%]
postgres-target/tests/test_pkg_order_mgmt.py::test_list_customer_orders_defaults_page_arguments PASSED [ 52%]
postgres-target/tests/test_pkg_order_mgmt.py::test_list_customer_orders_for_customer_without_orders PASSED [ 53%]
postgres-target/tests/test_pkg_order_mgmt.py::test_load_order_totals_uses_session_temp_table PASSED [ 54%]
postgres-target/tests/test_pkg_order_mgmt.py::test_load_order_totals_for_customer_without_orders PASSED [ 54%]
postgres-target/tests/test_pkg_order_mgmt.py::test_load_order_totals_error_is_mapped PASSED [ 55%]
postgres-target/tests/test_pkg_order_mgmt.py::test_summarize_order_counts_lines_and_reverse_loop_marker PASSED [ 56%]
postgres-target/tests/test_pkg_order_mgmt.py::test_summarize_order_reports_null_amount_line PASSED [ 57%]
postgres-target/tests/test_pkg_order_mgmt.py::test_summarize_order_with_no_lines_still_returns_marker PASSED [ 58%]
postgres-target/tests/test_pkg_order_mgmt.py::test_summarize_order_for_missing_order PASSED [ 59%]
postgres-target/tests/test_pkg_order_mgmt.py::test_dynamic_sql_uses_quoted_identifiers PASSED [ 59%]
postgres-target/tests/test_pkg_order_mgmt.py::test_functions_are_schema_qualified PASSED [ 60%]
postgres-target/tests/test_schema_and_types.py::test_type_mapping[customers-avatar_blob] PASSED [ 61%]
postgres-target/tests/test_schema_and_types.py::test_type_mapping[customers-credit_limit] PASSED [ 62%]
postgres-target/tests/test_schema_and_types.py::test_type_mapping[customers-customer_code] PASSED [ 63%]
postgres-target/tests/test_schema_and_types.py::test_type_mapping[customers-customer_id] PASSED [ 63%]
postgres-target/tests/test_schema_and_types.py::test_type_mapping[customers-display_name] PASSED [ 64%]
postgres-target/tests/test_schema_and_types.py::test_type_mapping[customers-external_ref] PASSED [ 65%]
postgres-target/tests/test_schema_and_types.py::test_type_mapping[customers-joined_on] PASSED [ 66%]
postgres-target/tests/test_schema_and_types.py::test_type_mapping[customers-profile_note] PASSED [ 67%]
postgres-target/tests/test_schema_and_types.py::test_type_mapping[invoice_lines-quantity] PASSED [ 68%]
postgres-target/tests/test_schema_and_types.py::test_type_mapping[order_lines-discount_rate] PASSED [ 68%]
postgres-target/tests/test_schema_and_types.py::test_type_mapping[order_lines-quantity] PASSED [ 69%]
postgres-target/tests/test_schema_and_types.py::test_type_mapping[orders-order_id] PASSED [ 70%]
postgres-target/tests/test_schema_and_types.py::test_type_mapping[orders-ordered_at] PASSED [ 71%]
postgres-target/tests/test_schema_and_types.py::test_type_mapping[orders-total_amount] PASSED [ 72%]
postgres-target/tests/test_schema_and_types.py::test_type_mapping[products-weight_kg] PASSED [ 72%]
postgres-target/tests/test_schema_and_types.py::test_varchar_char_length_is_characters_not_bytes PASSED [ 73%]
postgres-target/tests/test_schema_and_types.py::test_byte_semantics_check_rejects_oversized_multibyte_name PASSED [ 74%]
postgres-target/tests/test_schema_and_types.py::test_raw16_became_bytea_with_length_check PASSED [ 75%]
postgres-target/tests/test_schema_and_types.py::test_clob_and_blob_round_trip PASSED [ 76%]
postgres-target/tests/test_schema_and_types.py::test_oracle_empty_string_becomes_null PASSED [ 77%]
postgres-target/tests/test_schema_and_types.py::test_empty_string_elsewhere_is_not_null PASSED [ 77%]
postgres-target/tests/test_schema_and_types.py::test_check_constraint_still_rejects_empty_string_written_around_trigger PASSED [ 78%]
postgres-target/tests/test_schema_and_types.py::test_trigger_assigns_key_and_normalises_code PASSED [ 79%]
postgres-target/tests/test_schema_and_types.py::test_caller_supplied_key_wins_over_sequence PASSED [ 80%]
postgres-target/tests/test_schema_and_types.py::test_sequences_start_values_and_alignment PASSED [ 81%]
postgres-target/tests/test_schema_and_types.py::test_derived_totals_trigger_matches_source_behaviour PASSED [ 81%]
postgres-target/tests/test_schema_and_types.py::test_payment_trigger_decode_translation PASSED [ 82%]
postgres-target/tests/test_schema_and_types.py::test_audit_trigger_defaults PASSED [ 83%]
postgres-target/tests/test_schema_and_types.py::test_boundary_dates_survived PASSED [ 84%]
postgres-target/tests/test_schema_and_types.py::test_object_counts PASSED [ 85%]
postgres-target/tests/test_views_and_oracle_only_objects.py::test_v_order_summary_labels_unbilled_orders PASSED [ 86%]
postgres-target/tests/test_views_and_oracle_only_objects.py::test_v_order_summary_covers_every_order PASSED [ 86%]
postgres-target/tests/test_views_and_oracle_only_objects.py::test_v_order_summary_joins_customer_columns PASSED [ 87%]
postgres-target/tests/test_views_and_oracle_only_objects.py::test_v_customer_balance_reproduces_the_oracle_fan_out PASSED [ 88%]
postgres-target/tests/test_views_and_oracle_only_objects.py::test_v_customer_balance_deduped_gives_the_correct_figure PASSED [ 89%]
postgres-target/tests/test_views_and_oracle_only_objects.py::test_v_customer_balance_keeps_customers_without_orders PASSED [ 90%]
postgres-target/tests/test_views_and_oracle_only_objects.py::test_both_balance_views_agree_when_there_is_one_payment PASSED [ 90%]
postgres-target/tests/test_views_and_oracle_only_objects.py::test_v_recent_orders_is_ordered_and_capped PASSED [ 91%]
postgres-target/tests/test_views_and_oracle_only_objects.py::test_current_orders_view_replaces_the_synonym PASSED [ 92%]
postgres-target/tests/test_views_and_oracle_only_objects.py::test_current_orders_view_is_updatable_like_a_synonym PASSED [ 93%]
postgres-target/tests/test_views_and_oracle_only_objects.py::test_materialized_view_is_populated_and_stale_until_refreshed PASSED [ 94%]
postgres-target/tests/test_views_and_oracle_only_objects.py::test_materialized_view_has_the_unique_index_for_concurrent_refresh PASSED [ 95%]
postgres-target/tests/test_views_and_oracle_only_objects.py::test_gtt_template_stays_empty PASSED [ 95%]
postgres-target/tests/test_views_and_oracle_only_objects.py::test_ensure_gtt_is_idempotent_within_a_session PASSED [ 96%]
postgres-target/tests/test_views_and_oracle_only_objects.py::test_gtt_rows_are_session_private PASSED [ 97%]
postgres-target/tests/test_views_and_oracle_only_objects.py::test_index_organized_table_is_clustered_on_its_primary_key PASSED [ 98%]
postgres-target/tests/test_views_and_oracle_only_objects.py::test_bitmap_index_replacement_exists PASSED [ 99%]
postgres-target/tests/test_views_and_oracle_only_objects.py::test_partial_index_replacement_is_used_for_open_orders PASSED [100%]

============================= 122 passed in 5.60s ==============================
```
