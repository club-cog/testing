CREATE OR REPLACE PACKAGE ut_pkg_customer_hier AS
    --%suite(pkg_customer_hier characterization)
    --%suitepath(estate.oracle)
    --%displayname(Characterization of pkg_customer_hier on Oracle 19c)
    --%rollback(auto)

    --%beforeall
    PROCEDURE suite_setup;

    --%beforeeach
    PROCEDURE test_setup;

    -- descendant_count

    --%test(descendant_count counts the root itself along with its descendants)
    PROCEDURE count_includes_the_root;

    --%test(descendant_count on a middle node counts only that subtree)
    PROCEDURE count_of_subtree;

    --%test(descendant_count on a leaf returns 1)
    PROCEDURE count_of_leaf_is_one;

    --%test(descendant_count returns 0 for a customer id that does not exist)
    PROCEDURE count_unknown_root_is_zero;

    --%test(descendant_count returns 0 for a NULL root)
    PROCEDURE count_null_root_is_zero;

    --%test(descendant_count raises ORA-01436 when the parent links form a loop)
    PROCEDURE count_raises_on_loop;

    -- print_tree

    --%test(print_tree indents two spaces per level and orders siblings by code)
    PROCEDURE tree_indents_and_orders;

    --%test(print_tree emits no line for a root that does not exist)
    PROCEDURE tree_unknown_root_is_silent;

    --%test(print_tree walks through a held customer without filtering it out)
    PROCEDURE tree_ignores_status;

    -- list_ancestors

    --%test(list_ancestors returns the customer first and the root last)
    PROCEDURE ancestors_self_then_parents;

    --%test(list_ancestors returns a single row for a customer with no parent)
    PROCEDURE ancestors_of_root_is_self;

    --%test(list_ancestors returns nothing for a customer id that does not exist)
    PROCEDURE ancestors_unknown_is_empty;

    -- find_unordered_customers

    --%test(find_unordered_customers lists active customers with no order in 90 days)
    PROCEDURE unordered_lists_quiet_actives;

    --%test(find_unordered_customers drops a customer as soon as a recent order exists)
    PROCEDURE unordered_drops_new_orderer;

    --%test(find_unordered_customers ignores inactive and held customers)
    PROCEDURE unordered_ignores_non_active;

    -- empty string and trigger behaviour that the hierarchy data depends on

    --%test(an empty string preferred_channel is stored as NULL and passes the check)
    PROCEDURE empty_channel_is_null;

    --%test(the customers BEFORE INSERT trigger upper cases and trims the code)
    PROCEDURE trigger_normalizes_code;
END ut_pkg_customer_hier;
/
