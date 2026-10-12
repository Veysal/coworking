-- 1. Поиск без индекса и с индексом
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM bookings WHERE user_id = 42 ORDER BY lower(period) DESC LIMIT 20;
DROP INDEX bookings_user_start;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM bookings WHERE user_id = 42 ORDER BY lower(period) DESC LIMIT 20;

CREATE INDEX bookings_user_start ON bookings (user_id, (lower(period)) DESC) INCLUDE (status, room_id);

-- 2. Диапазоны: оператор && использует gist-индекс от EXCLUDE-ограничения
EXPLAIN (ANALYZE) SELECT count(*) FROM bookings
WHERE room_id = 5 AND period && tstzrange(now(), now() + interval '30 days');

-- 3. Полнотекстовый поиск vs ILIKE
EXPLAIN (ANALYZE) SELECT id FROM rooms WHERE search_vec @@ websearch_to_tsquery('russian', 'проектор доска');
EXPLAIN (ANALYZE) SELECT id FROM rooms WHERE description ILIKE '%проектор%';   
SELECT id, name, ts_rank(search_vec, q) AS rank
FROM rooms, websearch_to_tsquery('russian', 'тихая комната -проектор') q
WHERE search_vec @@ q ORDER BY rank DESC LIMIT 5;                         

-- 4. Нечёткий поиск (pg_trgm)
SET pg_trgm.similarity_threshold = 0.2;
SELECT name, similarity(name, 'Гама') FROM rooms WHERE name % 'Гама' ORDER BY 2 DESC;

-- 5. JSONB: @> использует GIN jsonb_path_ops
EXPLAIN (ANALYZE) SELECT name FROM rooms WHERE equipment @> '{"projector": true, "video_conference": true}';
SELECT name, equipment->>'screens' AS screens FROM rooms WHERE (equipment->>'screens')::int >= 2;
SELECT name, jsonb_path_query(equipment, '$.screens') AS screens FROM rooms LIMIT 3; 

-- 6. Partial index: индекс только по «ожидающим» броням
EXPLAIN (ANALYZE) SELECT * FROM bookings WHERE status = 'pending' ORDER BY created_at LIMIT 10;
SELECT pg_size_pretty(pg_relation_size('bookings_pending')) AS partial,
       pg_size_pretty(pg_relation_size('bookings_room_start')) AS full_btree;

-- 7. Размеры всех индексов таблицы
SELECT indexrelid::regclass AS index, pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_index WHERE indrelid = 'bookings'::regclass ORDER BY pg_relation_size(indexrelid) DESC;

-- 8. Партиционирование: смотрим pruning
EXPLAIN SELECT * FROM audit_log WHERE created_at >= date_trunc('month', now());
-- В плане только одна партиция вместо всех.
SELECT tableoid::regclass AS partition, count(*) FROM audit_log GROUP BY 1 ORDER BY 1;
