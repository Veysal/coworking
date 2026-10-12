
WITH RECURSIVE t AS (
    SELECT id, parent_id, name, 0 AS depth, name::text AS path FROM locations WHERE parent_id IS NULL
    UNION ALL
    SELECT l.id, l.parent_id, l.name, t.depth + 1, t.path || ' / ' || l.name
    FROM locations l JOIN t ON l.parent_id = t.id
)
SELECT repeat('  ', depth) || name AS tree, (SELECT count(*) FROM rooms r WHERE r.location_id = t.id) AS rooms
FROM t ORDER BY path;

SELECT p.building, r.name, count(*) AS cnt,
       rank()       OVER w AS rnk,
       dense_rank() OVER w AS dense,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY p.building), 1) AS pct_in_building
FROM bookings b JOIN rooms r ON r.id = b.room_id JOIN v_room_places p ON p.room_id = r.id
WHERE b.status = 'confirmed'
GROUP BY p.building, r.name
WINDOW w AS (PARTITION BY p.building ORDER BY count(*) DESC)
ORDER BY p.building, rnk LIMIT 20;


SELECT day, hours, sum(hours) OVER (ORDER BY day) AS running_total,
       round(avg(hours) OVER (ORDER BY day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 1) AS avg_7d,
       hours - lag(hours) OVER (ORDER BY day) AS delta_vs_prev
FROM (SELECT day, extract(epoch FROM sum(booked)) / 3600 AS hours FROM mv_room_daily GROUP BY day) d
ORDER BY day DESC LIMIT 14;

SELECT room_id, min(day) AS from_day, max(day) AS to_day, count(*) AS days
FROM (SELECT room_id, day, day - (row_number() OVER (PARTITION BY room_id ORDER BY day))::int AS grp
      FROM mv_room_daily WHERE room_id = 1) s
GROUP BY room_id, grp HAVING count(*) >= 3 ORDER BY from_day DESC LIMIT 5;


SELECT r.name, nb.start_at, nb.title
FROM rooms r
LEFT JOIN LATERAL (SELECT lower(period) AS start_at, title FROM bookings b
                   WHERE b.room_id = r.id AND b.status <> 'cancelled' AND lower(b.period) > now()
                   ORDER BY lower(b.period) LIMIT 1) nb ON true
ORDER BY nb.start_at LIMIT 10;


SELECT p.building, extract(isodow FROM lower(b.period))::int AS weekday,
       count(*) FILTER (WHERE b.status = 'confirmed') AS confirmed,
       count(*) FILTER (WHERE b.status = 'cancelled') AS cancelled
FROM bookings b JOIN v_room_places p ON p.room_id = b.room_id
GROUP BY ROLLUP (p.building, extract(isodow FROM lower(b.period))::int)
ORDER BY 1 NULLS LAST, 2 NULLS LAST;

SELECT g AS window_start FROM generate_series(
         date_trunc('day', now() + interval '1 day') + interval '8 hours',
         date_trunc('day', now() + interval '1 day') + interval '18 hours', interval '1 hour') g
WHERE NOT EXISTS (SELECT 1 FROM bookings b WHERE b.room_id = 3 AND b.status <> 'cancelled'
                  AND b.period && tstzrange(g, g + interval '2 hours'));

INSERT INTO rooms (location_id, name, capacity) VALUES (3, 'Альфа', 5)
ON CONFLICT (location_id, name) DO UPDATE SET capacity = EXCLUDED.capacity
RETURNING id, name, capacity, (xmax = 0) AS inserted;

SELECT tstzrange('2026-10-10 10:00+00', '2026-10-10 12:00+00') && tstzrange('2026-10-10 11:00+00', '2026-10-10 13:00+00') AS overlap,
       tstzrange('2026-10-10 10:00+00', '2026-10-10 12:00+00') * tstzrange('2026-10-10 11:00+00', '2026-10-10 13:00+00') AS intersection,
       tstzrange('2026-10-10 10:00+00', '2026-10-10 12:00+00') -|- tstzrange('2026-10-10 12:00+00', '2026-10-10 13:00+00') AS adjacent;
