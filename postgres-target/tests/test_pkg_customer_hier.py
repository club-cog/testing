"""Behaviour of the converted PKG_CUSTOMER_HIER functions.

Seeded hierarchy, with customer_code uppercased by trg_customers_bi:

    1001 C-ROOT
      1002 C-EAST
        1004 C-EAST-1
          1005 C-EAST-1-A
            1006 C-EAST-1-A-1
      1003 C-WEST

1003 is inserted before 1002 in the seed, so sibling order can only come from
customer_code, which is what ORDER SIBLINGS BY did.
"""

from __future__ import annotations

from conftest import one, rows, scalar


def test_print_tree_walks_depth_first_in_sibling_code_order(cur):
    tree = rows(cur, "SELECT * FROM pkg_customer_hier.print_tree(1001)")
    assert [(r[0], r[3]) for r in tree] == [
        (1001, 1),
        (1002, 2),
        (1004, 3),
        (1005, 4),
        (1006, 5),
        (1003, 2),
    ]


def test_print_tree_indents_by_level_like_lpad(cur):
    paths = [r[4] for r in rows(cur, "SELECT * FROM pkg_customer_hier.print_tree(1001)")]
    assert paths == [
        "C-ROOT",
        "  C-EAST",
        "    C-EAST-1",
        "      C-EAST-1-A",
        "        C-EAST-1-A-1",
        "  C-WEST",
    ]


def test_print_tree_from_mid_hierarchy(cur):
    tree = rows(cur, "SELECT * FROM pkg_customer_hier.print_tree(1004)")
    assert [(r[0], r[3]) for r in tree] == [(1004, 1), (1005, 2), (1006, 3)]


def test_print_tree_leaf_returns_only_itself(cur):
    tree = rows(cur, "SELECT * FROM pkg_customer_hier.print_tree(1006)")
    assert [(r[0], r[3]) for r in tree] == [(1006, 1)]


def test_print_tree_unknown_root_returns_nothing(cur):
    assert rows(cur, "SELECT * FROM pkg_customer_hier.print_tree(999999)") == []


def test_list_ancestors_climbs_five_levels(cur):
    found = rows(cur, "SELECT * FROM pkg_customer_hier.list_ancestors(1006)")
    assert [(r[0], r[3]) for r in found] == [
        (1006, 1),
        (1005, 2),
        (1004, 3),
        (1002, 4),
        (1001, 5),
    ]
    assert found[-1][2] is None, "the root has no parent"


def test_list_ancestors_of_root_is_just_the_root(cur):
    assert [
        r[0] for r in rows(cur, "SELECT * FROM pkg_customer_hier.list_ancestors(1001)")
    ] == [1001]


def test_list_ancestors_of_orphan_customer(cur):
    assert [
        r[0] for r in rows(cur, "SELECT * FROM pkg_customer_hier.list_ancestors(1008)")
    ] == [1008]


def test_list_ancestors_unknown_customer_returns_nothing(cur):
    assert rows(cur, "SELECT * FROM pkg_customer_hier.list_ancestors(999999)") == []


def test_find_unordered_customers_excludes_recent_orderers(cur):
    """MINUS became EXCEPT. 1003 ordered five days ago and 1009 has a far future
    order date, so both fall inside the 90 day window. 1007 is status I and was
    never in the left leg at all."""
    found = [r[0] for r in rows(cur, "SELECT * FROM pkg_customer_hier.find_unordered_customers()")]
    assert found == [1001, 1002, 1004, 1005, 1006, 1008, 1010]
    assert 1003 not in found
    assert 1009 not in found
    assert 1007 not in found


def test_find_unordered_customers_reacts_to_a_new_order(cur):
    cur.execute(
        "INSERT INTO retail.orders (order_number, customer_id, ordered_at)"
        " VALUES ('ORD-H001', 1010, retail.sysdate())"
    )
    found = [r[0] for r in rows(cur, "SELECT * FROM pkg_customer_hier.find_unordered_customers()")]
    assert 1010 not in found


def test_find_unordered_customers_ignores_orders_older_than_ninety_days(cur):
    cur.execute(
        "INSERT INTO retail.orders (order_number, customer_id, ordered_at)"
        " VALUES ('ORD-H002', 1010, retail.sysdate() - interval '91 days')"
    )
    found = [r[0] for r in rows(cur, "SELECT * FROM pkg_customer_hier.find_unordered_customers()")]
    assert 1010 in found


def test_find_unordered_customers_deduplicates_like_minus(cur):
    """EXCEPT removes duplicates, so two recent orders still remove one row."""
    cur.execute(
        "INSERT INTO retail.orders (order_number, customer_id, ordered_at)"
        " VALUES ('ORD-H003', 1010, retail.sysdate()), ('ORD-H004', 1010, retail.sysdate())"
    )
    found = [r[0] for r in rows(cur, "SELECT * FROM pkg_customer_hier.find_unordered_customers()")]
    assert found.count(1010) == 0
    assert len(found) == len(set(found))


def test_descendant_count_includes_the_root_row(cur):
    """Preserved source behaviour: the CONNECT BY set contains the root, so the
    count is descendants plus one."""
    assert scalar(cur, "SELECT pkg_customer_hier.descendant_count(1001)") == 6
    assert scalar(cur, "SELECT pkg_customer_hier.descendant_count(1002)") == 4
    assert scalar(cur, "SELECT pkg_customer_hier.descendant_count(1006)") == 1


def test_descendant_count_unknown_root_is_zero(cur):
    assert scalar(cur, "SELECT pkg_customer_hier.descendant_count(999999)") == 0


def test_descendant_count_follows_a_reparent(cur):
    cur.execute("UPDATE retail.customers SET parent_customer_id = 1001 WHERE customer_id = 1008")
    assert scalar(cur, "SELECT pkg_customer_hier.descendant_count(1001)") == 7


def test_hierarchy_functions_are_schema_qualified(cur):
    found = {
        name
        for (name,) in rows(
            cur,
            "SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace"
            " WHERE n.nspname = 'pkg_customer_hier'",
        )
    }
    assert found == {
        "print_tree",
        "list_ancestors",
        "find_unordered_customers",
        "descendant_count",
    }


def test_deep_hierarchy_level_matches_ancestor_depth(cur):
    level = scalar(
        cur,
        "SELECT hierarchy_level FROM pkg_customer_hier.print_tree(1001)"
        " WHERE customer_id = 1006",
    )
    depth = scalar(
        cur,
        "SELECT depth FROM pkg_customer_hier.list_ancestors(1006) WHERE customer_id = 1001",
    )
    assert level == depth == 5


def test_one_row_per_customer_in_tree(cur):
    assert one(
        cur,
        "SELECT count(*), count(DISTINCT customer_id) FROM pkg_customer_hier.print_tree(1001)",
    ) == (6, 6)
