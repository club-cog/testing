-- These triggers are intentionally row-level and old-fashioned.

CREATE OR REPLACE TRIGGER trg_customers_bi
BEFORE INSERT ON customers
FOR EACH ROW
BEGIN
    IF :NEW.customer_id IS NULL THEN
        :NEW.customer_id := seq_customers.NEXTVAL;
    END IF;

    :NEW.customer_code := UPPER(TRIM(:NEW.customer_code));
    :NEW.status := NVL(:NEW.status, 'A');
END;
/

CREATE OR REPLACE TRIGGER trg_addresses_bi
BEFORE INSERT ON addresses
FOR EACH ROW
BEGIN
    IF :NEW.address_id IS NULL THEN
        :NEW.address_id := seq_addresses.NEXTVAL;
    END IF;
    :NEW.country_code := NVL(UPPER(:NEW.country_code), 'ZZ');
END;
/

CREATE OR REPLACE TRIGGER trg_products_bi
BEFORE INSERT ON products
FOR EACH ROW
BEGIN
    IF :NEW.product_id IS NULL THEN
        :NEW.product_id := seq_products.NEXTVAL;
    END IF;
    :NEW.sku := UPPER(TRIM(:NEW.sku));
END;
/

CREATE OR REPLACE TRIGGER trg_orders_bi
BEFORE INSERT ON orders
FOR EACH ROW
BEGIN
    IF :NEW.order_id IS NULL THEN
        :NEW.order_id := seq_orders.NEXTVAL;
    END IF;

    :NEW.order_number := UPPER(TRIM(:NEW.order_number));
    :NEW.order_status := NVL(:NEW.order_status, 'OPEN');
    :NEW.total_amount := NVL(:NEW.total_amount, 0);
END;
/

CREATE OR REPLACE TRIGGER trg_invoices_bi
BEFORE INSERT ON invoices
FOR EACH ROW
BEGIN
    IF :NEW.invoice_id IS NULL THEN
        :NEW.invoice_id := seq_invoices.NEXTVAL;
    END IF;
    :NEW.invoice_number := UPPER(TRIM(:NEW.invoice_number));
END;
/
