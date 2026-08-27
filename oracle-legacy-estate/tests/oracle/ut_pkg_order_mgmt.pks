CREATE OR REPLACE PACKAGE ut_pkg_order_mgmt AS
    --%suite(pkg_order_mgmt characterization)
    --%suitepath(estate.oracle)
    --%displayname(Characterization of pkg_order_mgmt on Oracle 19c)
    --%rollback(auto)

    --%beforeall
    PROCEDURE suite_setup;

    --%afterall
    PROCEDURE suite_teardown;

    --%beforeeach
    PROCEDURE test_setup;

    -- create_order

    --%test(create_order defaults a NULL requester to BATCH and status OPEN)
    PROCEDURE create_null_requester_is_open;

    --%test(create_order with a named requester stores status HELD)
    PROCEDURE create_named_requester_is_held;

    --%test(create_order with the literal string BATCH stores status OPEN)
    PROCEDURE create_literal_batch_is_open;

    --%test(create_order treats an empty string requester as NULL)
    PROCEDURE create_empty_requester_is_batch;

    --%test(create_order publishes the new id in package state g_last_order_id)
    PROCEDURE create_publishes_package_state;

    --%test(create_order raises ORA-20901 on a duplicate order number)
    PROCEDURE create_duplicate_raises_20901;

    --%test(create_order rolls back to its savepoint when the duplicate is rejected)
    PROCEDURE create_duplicate_leaves_no_row;

    --%test(create_order leaves g_last_order_id at its previous value after a failure)
    PROCEDURE create_failure_keeps_state;

    --%test(create_order fails its own lookup when the trigger rewrites the order number)
    PROCEDURE create_untrimmed_number_fails;

    -- add_order_line

    --%test(add_order_line numbers the first line 1 and the next line 2)
    PROCEDURE add_line_numbers_sequentially;

    --%test(add_order_line stores quantity times unit price as extended_amount)
    PROCEDURE add_line_computes_extended;

    --%test(add_order_line defaults a NULL quantity to 1)
    PROCEDURE add_line_null_quantity_is_one;

    --%test(add_order_line with a NULL unit price raises ORA-01400)
    PROCEDURE add_line_null_price_raises;

    --%test(add_order_line leaves the order totals including 8.25 percent tax)
    PROCEDURE add_line_sets_order_totals;

    -- refresh_order_total

    --%test(refresh_order_total rounds a tax of exactly 0.825 up to 0.83)
    PROCEDURE refresh_rounds_tax_half_up;

    --%test(refresh_order_total rounds the discount to 2 decimals before taxing)
    PROCEDURE refresh_rounds_discount_first;

    --%test(refresh_order_total zeroes an order that has no lines)
    PROCEDURE refresh_order_without_lines;

    --%test(refresh_order_total is silent for an order id that does not exist)
    PROCEDURE refresh_unknown_order_is_silent;

    -- list_customer_orders

    --%test(list_customer_orders page 1 returns the two newest orders)
    PROCEDURE list_first_page;

    --%test(list_customer_orders page 2 returns the next two orders)
    PROCEDURE list_second_page;

    --%test(list_customer_orders returns a short final page)
    PROCEDURE list_partial_last_page;

    --%test(list_customer_orders defaults NULL paging to page 1 of 25)
    PROCEDURE list_null_paging_defaults;

    --%test(list_customer_orders returns nothing for a page size of 0)
    PROCEDURE list_zero_page_size;

    --%test(list_customer_orders returns nothing for an unknown customer)
    PROCEDURE list_unknown_customer;

    -- load_order_totals

    --%test(load_order_totals writes one temp row per order with its line count)
    PROCEDURE load_totals_populates_gtt;

    --%test(load_order_totals writes 0 for an order whose total_amount is NULL)
    PROCEDURE load_totals_null_total_is_zero;

    --%test(load_order_totals deletes rows left by an earlier call)
    PROCEDURE load_totals_clears_previous;

    --%test(load_order_totals leaves the temp table empty for an unknown customer)
    PROCEDURE load_totals_unknown_customer;

    -- summarize_order

    --%test(summarize_order reports the line count and the last reverse loop marker)
    PROCEDURE summarize_reports_line_count;

    --%test(summarize_order reports NONE for an order with no invoice)
    PROCEDURE summarize_order_without_invoice;

    --%test(summarize_order reports the invoice id when one exists)
    PROCEDURE summarize_order_with_invoice;

    -- trigger maintained values

    --%test(the orders BEFORE INSERT trigger upper cases and trims order_number)
    PROCEDURE trigger_normalizes_order_number;

    --%test(updating a line quantity does not recompute extended_amount)
    PROCEDURE trigger_leaves_extended_amount;
END ut_pkg_order_mgmt;
/
