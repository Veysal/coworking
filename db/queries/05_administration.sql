
SELECT calls, round(total_exec_time::numeric, 1) AS total_ms, round(mean_exec_time::numeric, 2) AS mean_ms, left(query, 80) AS query
FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;

SELECT relname, pg_size_pretty(pg_total_relation_size(oid)) AS total, pg_size_pretty(pg_relation_size(oid)) AS heap
FROM pg_class WHERE relkind IN ('r','m','p') AND relnamespace = 'public'::regnamespace ORDER BY pg_total_relation_size(oid) DESC LIMIT 10;

SELECT relname, indexrelname, idx_scan, pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes ORDER BY idx_scan, pg_relation_size(indexrelid) DESC LIMIT 10;

SELECT relname, n_live_tup, n_dead_tup, last_autovacuum FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 5;
UPDATE bookings SET title = title WHERE id <= 5000;                     
SELECT pg_sleep(1), n_dead_tup FROM pg_stat_user_tables WHERE relname = 'bookings';
VACUUM (VERBOSE, ANALYZE) bookings;
SELECT pg_sleep(1), n_dead_tup FROM pg_stat_user_tables WHERE relname = 'bookings';

SELECT pid, usename, state, wait_event_type, left(query, 60) AS query FROM pg_stat_activity WHERE datname = current_database();

SELECT round(100.0 * sum(blks_hit) / nullif(sum(blks_hit + blks_read), 0), 1) AS cache_hit_pct FROM pg_stat_database WHERE datname = current_database();

SELECT create_audit_partition((now() + interval '8 months')::date);

