CREATE OR REPLACE PACKAGE pkg_billing AS
    PROCEDURE issue_invoice (
        p_order_id        IN orders.order_id%TYPE,
        p_invoice_id      OUT invoices.invoice_id%TYPE
    );

    PROCEDURE apply_payment (
        p_invoice_id      IN payments.invoice_id%TYPE,
        p_amount          IN payments.amount_paid%TYPE,
        p_method          IN payments.payment_method%TYPE
    );

    PROCEDURE rebuild_invoice_totals (
        p_invoice_id      IN invoices.invoice_id%TYPE
    );

    PROCEDURE write_billing_log (
        p_entity_id       IN audit_log.entity_id%TYPE,
        p_action_code     IN audit_log.action_code%TYPE,
        p_payload         IN VARCHAR2
    );
END pkg_billing;
/
