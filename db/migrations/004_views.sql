CREATE VIEW v_room_places WITH (security_invoker = true) AS
SELECT r.id AS room_id,
       coalesce(b.name, f.name)                      AS building,
       CASE WHEN b.id IS NULL THEN NULL ELSE f.name END AS floor,
       CASE WHEN b.id IS NULL THEN f.name ELSE b.name || ', ' || f.name END AS place
FROM rooms r
JOIN locations f ON f.id = r.location_id
LEFT JOIN locations b ON b.id = f.parent_id;

CREATE VIEW v_bookings_full WITH (security_invoker = true) AS
SELECT b.id, b.room_id, r.name AS room_name, p.place,
       b.user_id, u.full_name AS user_name,
       lower(b.period) AS start_at, upper(b.period) AS end_at,
       (extract(epoch FROM b.duration) / 60)::int AS duration_min,
       b.status, b.title, b.created_at
FROM bookings b
JOIN rooms r        ON r.id = b.room_id
JOIN v_room_places p ON p.room_id = r.id
JOIN users u        ON u.id = b.user_id;


CREATE MATERIALIZED VIEW mv_room_daily AS
SELECT b.room_id,
       (lower(b.period) AT TIME ZONE 'UTC')::date AS day,
       count(*)        AS bookings_cnt,
       sum(b.duration) AS booked
FROM bookings b
WHERE b.status = 'confirmed'
GROUP BY 1, 2;
CREATE UNIQUE INDEX mv_room_daily_uq ON mv_room_daily (room_id, day);  

CREATE MATERIALIZED VIEW mv_user_stats AS
SELECT u.id AS user_id, u.full_name,
       count(b.id)                                   AS bookings_total,
       count(b.id) FILTER (WHERE b.status = 'confirmed') AS confirmed,
       count(b.id) FILTER (WHERE b.status = 'cancelled') AS cancelled,
       coalesce(sum(b.duration) FILTER (WHERE b.status = 'confirmed'), interval '0') AS booked,
       max(lower(b.period)) AS last_booking
FROM users u LEFT JOIN bookings b ON b.user_id = u.id
GROUP BY u.id, u.full_name;
CREATE UNIQUE INDEX mv_user_stats_uq ON mv_user_stats (user_id);
