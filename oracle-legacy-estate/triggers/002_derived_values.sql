CREATE OR REPLACE TRIGGER trg_order_lines_ai
AFTER INSERT OR UPDATE OF quantity, unit_price, discount_rate ON order_lines
FOR EACH ROW
BEGIN
    UPDATE orders
    SET subtotal_amount = (
            SELECT NVL(SUM(extended_amount), 0)
            FROM order_lines
            WHERE order_id = :NEW.order_id
        ),
        total_amount = (
            SELECT NVL(SUM(extended_amount), 0)
            FROM order_lines
            WHERE order_id = :NEW.order_id
        )
    WHERE order_id = :NEW.order_id;
END;
/

CREATE OR REPLACE TRIGGER trg_payments_ai
AFTER INSERT ON payments
FOR EACH ROW
BEGIN
    UPDATE invoices
    SET invoice_status = DECODE(invoice_status, 'VOID', 'VOID', 'PARTIAL')
    WHERE invoice_id = :NEW.invoice_id
      AND invoice_status <> 'PAID';
END;
/

CREATE OR REPLACE TRIGGER trg_audit_log_bi
BEFORE INSERT ON audit_log
FOR EACH ROW
BEGIN
    IF :NEW.audit_id IS NULL THEN
        :NEW.audit_id := seq_audit_log.NEXTVAL;
    END IF;
    IF :NEW.event_time IS NULL THEN
        :NEW.event_time := SYSDATE;
    END IF;
END;
/
