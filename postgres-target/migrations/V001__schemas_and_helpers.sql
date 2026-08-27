-- V001: schemas and the small helper layer the rest of the conversion leans on.
--
-- Oracle packages become PostgreSQL schemas, one schema per package. Table
-- objects that lived in the single Oracle schema move into "retail".
--
-- Source estate: oracle-legacy-estate/ (synthetic fixture, no real data).

CREATE SCHEMA IF NOT EXISTS retail;
CREATE SCHEMA IF NOT EXISTS pkg_order_mgmt;
CREATE SCHEMA IF NOT EXISTS pkg_billing;
CREATE SCHEMA IF NOT EXISTS pkg_customer_hier;

COMMENT ON SCHEMA retail IS 'Converted tables, views and sequences from the Oracle estate';
COMMENT ON SCHEMA pkg_order_mgmt IS 'Converted PKG_ORDER_MGMT';
COMMENT ON SCHEMA pkg_billing IS 'Converted PKG_BILLING';
COMMENT ON SCHEMA pkg_customer_hier IS 'Converted PKG_CUSTOMER_HIER';

-- SYSDATE replacement.
--
-- Oracle SYSDATE returns the database server clock with second resolution and
-- it is NOT frozen for the duration of a transaction. PostgreSQL now() and
-- localtimestamp are frozen at transaction start, so clock_timestamp() is the
-- closer match. Truncating to second keeps the Oracle DATE resolution.
CREATE OR REPLACE FUNCTION retail.sysdate()
RETURNS timestamp(0) WITHOUT TIME ZONE
LANGUAGE sql
AS $$
    SELECT clock_timestamp()::timestamp(0);
$$;

COMMENT ON FUNCTION retail.sysdate() IS
    'Stand-in for Oracle SYSDATE: server clock, second resolution, not transaction-frozen';

-- Oracle treats the empty string as NULL. PostgreSQL does not. The estate
-- relies on that behaviour in two places (customers.preferred_channel and
-- addresses.validated_flag, both DEFAULT '' with a CHECK (col <> '')), so the
-- normalisation is made explicit here and applied by trigger.
CREATE OR REPLACE FUNCTION retail.oracle_empty_to_null(p_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT nullif(p_value, '');
$$;

COMMENT ON FUNCTION retail.oracle_empty_to_null(text) IS
    'Reproduces Oracle empty-string-is-NULL semantics for legacy loader input';
