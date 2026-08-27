-- V007: triggers.
--
-- The Oracle estate assigns keys and normalises values in row-level BEFORE
-- INSERT triggers and maintains derived totals in AFTER row triggers. The port
-- keeps the same shape so behaviour, including the parts that are arguably
-- wrong, matches the source. PostgreSQL needs a named trigger function per
-- trigger, so each Oracle trigger becomes one function plus one trigger.

-- Key assignment and normalisation -------------------------------------------

CREATE OR REPLACE FUNCTION retail.trg_customers_bi()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.customer_id IS NULL THEN
        NEW.customer_id := nextval('retail.seq_customers');
    END IF;

    NEW.customer_code := upper(btrim(NEW.customer_code));
    NEW.status := COALESCE(NEW.status, 'A');
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_customers_bi
BEFORE INSERT ON retail.customers
FOR EACH ROW EXECUTE FUNCTION retail.trg_customers_bi();

CREATE OR REPLACE FUNCTION retail.trg_addresses_bi()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.address_id IS NULL THEN
        NEW.address_id := nextval('retail.seq_addresses');
    END IF;
    NEW.country_code := COALESCE(upper(NEW.country_code), 'ZZ');
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_addresses_bi
BEFORE INSERT ON retail.addresses
FOR EACH ROW EXECUTE FUNCTION retail.trg_addresses_bi();

CREATE OR REPLACE FUNCTION retail.trg_products_bi()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.product_id IS NULL THEN
        NEW.product_id := nextval('retail.seq_products');
    END IF;
    NEW.sku := upper(btrim(NEW.sku));
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_products_bi
BEFORE INSERT ON retail.products
FOR EACH ROW EXECUTE FUNCTION retail.trg_products_bi();

CREATE OR REPLACE FUNCTION retail.trg_orders_bi()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.order_id IS NULL THEN
        NEW.order_id := nextval('retail.seq_orders');
    END IF;

    NEW.order_number := upper(btrim(NEW.order_number));
    NEW.order_status := COALESCE(NEW.order_status, 'OPEN');
    NEW.total_amount := COALESCE(NEW.total_amount, 0);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_orders_bi
BEFORE INSERT ON retail.orders
FOR EACH ROW EXECUTE FUNCTION retail.trg_orders_bi();

CREATE OR REPLACE FUNCTION retail.trg_invoices_bi()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.invoice_id IS NULL THEN
        NEW.invoice_id := nextval('retail.seq_invoices');
    END IF;
    NEW.invoice_number := upper(btrim(NEW.invoice_number));
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_invoices_bi
BEFORE INSERT ON retail.invoices
FOR EACH ROW EXECUTE FUNCTION retail.trg_invoices_bi();

-- Empty string handling -------------------------------------------------------
--
-- Not present in the Oracle source because Oracle does it in the engine:
-- DEFAULT '' stores NULL and CHECK (col <> '') can never fire. Without these
-- triggers the legacy loader's empty strings would either be stored as real
-- empty strings or rejected by the CHECK constraint, both of which change
-- behaviour. Applied on UPDATE too, for the same reason.

CREATE OR REPLACE FUNCTION retail.trg_customers_empty_string()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.preferred_channel := retail.oracle_empty_to_null(NEW.preferred_channel);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_customers_empty_string
BEFORE INSERT OR UPDATE ON retail.customers
FOR EACH ROW EXECUTE FUNCTION retail.trg_customers_empty_string();

CREATE OR REPLACE FUNCTION retail.trg_addresses_empty_string()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.validated_flag := retail.oracle_empty_to_null(NEW.validated_flag);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_addresses_empty_string
BEFORE INSERT OR UPDATE ON retail.addresses
FOR EACH ROW EXECUTE FUNCTION retail.trg_addresses_empty_string();

-- Derived values --------------------------------------------------------------
--
-- Faithful port, including the source quirk that total_amount is set to the
-- untaxed subtotal by this trigger and then corrected by
-- pkg_order_mgmt.refresh_order_total. PostgreSQL runs the AFTER row trigger
-- once per row exactly like Oracle, and there is no mutating-table restriction
-- to work around.

CREATE OR REPLACE FUNCTION retail.trg_order_lines_ai()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    l_total numeric(14, 2);
BEGIN
    SELECT COALESCE(SUM(extended_amount), 0)
    INTO l_total
    FROM retail.order_lines
    WHERE order_id = NEW.order_id;

    UPDATE retail.orders
    SET subtotal_amount = l_total,
        total_amount = l_total
    WHERE order_id = NEW.order_id;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_order_lines_ai
AFTER INSERT OR UPDATE OF quantity, unit_price, discount_rate ON retail.order_lines
FOR EACH ROW EXECUTE FUNCTION retail.trg_order_lines_ai();

CREATE OR REPLACE FUNCTION retail.trg_payments_ai()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    -- Oracle DECODE(invoice_status, 'VOID', 'VOID', 'PARTIAL')
    UPDATE retail.invoices
    SET invoice_status = CASE WHEN invoice_status = 'VOID' THEN 'VOID' ELSE 'PARTIAL' END
    WHERE invoice_id = NEW.invoice_id
      AND invoice_status <> 'PAID';

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_payments_ai
AFTER INSERT ON retail.payments
FOR EACH ROW EXECUTE FUNCTION retail.trg_payments_ai();

CREATE OR REPLACE FUNCTION retail.trg_audit_log_bi()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.audit_id IS NULL THEN
        NEW.audit_id := nextval('retail.seq_audit_log');
    END IF;
    IF NEW.event_time IS NULL THEN
        NEW.event_time := retail.sysdate();
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_audit_log_bi
BEFORE INSERT ON retail.audit_log
FOR EACH ROW EXECUTE FUNCTION retail.trg_audit_log_bi();
