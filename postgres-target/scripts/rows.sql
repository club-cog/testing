SELECT 'customers' AS table_name, count(*) AS rows FROM retail.customers
UNION ALL SELECT 'addresses', count(*) FROM retail.addresses
UNION ALL SELECT 'products', count(*) FROM retail.products
UNION ALL SELECT 'price_tiers', count(*) FROM retail.price_tiers
UNION ALL SELECT 'orders', count(*) FROM retail.orders
UNION ALL SELECT 'order_lines', count(*) FROM retail.order_lines
UNION ALL SELECT 'invoices', count(*) FROM retail.invoices
UNION ALL SELECT 'invoice_lines', count(*) FROM retail.invoice_lines
UNION ALL SELECT 'payments', count(*) FROM retail.payments
UNION ALL SELECT 'audit_log', count(*) FROM retail.audit_log
ORDER BY 1;
