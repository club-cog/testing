SELECT 'tables' AS object_kind, count(*) AS n FROM information_schema.tables WHERE table_schema = 'retail' AND table_type = 'BASE TABLE'
UNION ALL SELECT 'views', count(*) FROM information_schema.views WHERE table_schema = 'retail'
UNION ALL SELECT 'materialized views', count(*) FROM pg_matviews WHERE schemaname = 'retail'
UNION ALL SELECT 'sequences', count(*) FROM information_schema.sequences WHERE sequence_schema = 'retail'
UNION ALL SELECT 'indexes', count(*) FROM pg_indexes WHERE schemaname = 'retail'
UNION ALL SELECT 'triggers', count(DISTINCT trigger_name) FROM information_schema.triggers WHERE trigger_schema = 'retail'
UNION ALL SELECT 'package functions', count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname LIKE 'pkg\_%'
UNION ALL SELECT 'retail functions', count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'retail'
ORDER BY 1;
