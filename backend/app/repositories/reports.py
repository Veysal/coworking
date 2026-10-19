UTILIZATION_SQL = """
WITH bounds AS (
    SELECT $1::date AS d1, $2::date AS d2, ($2::date - $1::date + 1) AS days
), per_room AS (
    SELECT r.id AS room_id, r.name AS room_name, p.building, p.place,
           count(b.id) FILTER (WHERE b.status = 'confirmed') AS bookings_cnt,
           coalesce(sum(b.duration) FILTER (WHERE b.status = 'confirmed'), interval '0') AS booked
    FROM rooms r
    JOIN v_room_places p ON p.room_id = r.id
    CROSS JOIN bounds bd
    LEFT JOIN bookings b ON b.room_id = r.id
         AND b.period && tstzrange(bd.d1::timestamp AT TIME ZONE 'UTC', (bd.d2 + 1)::timestamp AT TIME ZONE 'UTC', '[)')
    WHERE r.is_active
    GROUP BY r.id, r.name, p.building, p.place
)
SELECT p.room_id, p.room_name, p.place, p.bookings_cnt::int,
       round(extract(epoch FROM p.booked) / 3600, 1)::float AS booked_hours,
       round(100 * extract(epoch FROM p.booked) / 3600 / (bd.days * 12), 1)::float AS utilization_pct,
       rank() OVER (ORDER BY p.booked DESC)                              AS rank_overall,
       rank() OVER (PARTITION BY p.building ORDER BY p.booked DESC)      AS rank_in_building,
       round(100.0 * extract(epoch FROM p.booked)
             / nullif(sum(extract(epoch FROM p.booked)) OVER (), 0), 1)::float AS share_pct
FROM per_room p CROSS JOIN bounds bd
ORDER BY p.booked DESC, p.room_name
LIMIT $3
"""

DAILY_SQL = """
SELECT g::date AS day,
       coalesce(sum(d.bookings_cnt), 0)::int AS bookings_cnt,
       round(coalesce(extract(epoch FROM sum(d.booked)), 0) / 3600, 1)::float AS hours
FROM generate_series($1::date::timestamp, $2::date::timestamp, interval '1 day') AS g
LEFT JOIN mv_room_daily d ON d.day = g::date           -- читаем из материализованного представления
GROUP BY g
ORDER BY g
"""

TOP_USERS_SQL = """
WITH s AS (
    SELECT u.id, u.full_name, p.building, count(*) AS cnt, sum(b.duration) AS dur
    FROM bookings b
    JOIN users u ON u.id = b.user_id
    JOIN v_room_places p ON p.room_id = b.room_id
    WHERE b.status = 'confirmed' AND lower(b.period) >= now() - make_interval(days => $2::int)
    GROUP BY u.id, u.full_name, p.building
), ranked AS (
    SELECT s.*, rank() OVER (PARTITION BY building ORDER BY dur DESC) AS rnk
    FROM s
)
SELECT rnk::int AS rank, full_name, building, cnt::int AS bookings_cnt,
       round(extract(epoch FROM dur) / 3600, 1)::float AS hours
FROM ranked WHERE rnk <= $1
ORDER BY building, rnk, full_name
"""

SUMMARY_SQL = """
SELECT p.building, b.status::text AS status, count(*)::int AS bookings_cnt,
       round(extract(epoch FROM sum(b.duration)) / 3600, 1)::float AS hours,
       GROUPING(p.building, b.status) AS grouping_level
FROM bookings b
JOIN v_room_places p ON p.room_id = b.room_id
WHERE lower(b.period) >= $1::date::timestamp AT TIME ZONE 'UTC'
  AND lower(b.period) <  ($2::date + 1)::timestamp AT TIME ZONE 'UTC'
GROUP BY GROUPING SETS ((p.building, b.status), (p.building), (b.status), ())
ORDER BY p.building NULLS LAST, b.status NULLS LAST
"""

ACTIVE_USERS_SQL = """
SELECT user_id, full_name, bookings_total, confirmed, cancelled,
       round(extract(epoch FROM booked) / 3600, 1)::float AS hours, last_booking,
       round(100.0 * cancelled / nullif(bookings_total, 0), 1)::float AS cancel_rate_pct
FROM mv_user_stats
WHERE bookings_total > 0
ORDER BY booked DESC LIMIT $1
"""

AUDIT_SQL = """
SELECT id, created_at, table_name, op, row_id, actor_id, old_data, new_data
FROM audit_log
WHERE created_at >= now() - make_interval(days => $2::int)      -- partition pruning
  AND ($3::text IS NULL OR table_name = $3::text)
ORDER BY created_at DESC, id DESC
LIMIT $1
"""


async def utilization(conn, d1, d2, limit):
    return [dict(i) for i in await conn.fetch(UTILIZATION_SQL, d1, d2, limit)]

async def daily(conn, d1, d2):
    return [dict(i) for i in await conn.fetch(DAILY_SQL, d1, d2)]

async def top_users(conn, per_building, days):
    return [dict(i) for i in await conn.fetch(TOP_USERS_SQL, per_building, days)]


async def summary(conn, d1, d2):
    return [dict(i) for i in await conn.fetch(SUMMARY_SQL, d1, d2)]

async def active_users(conn, limit):
    return [dict(i) for i in await conn.fetch(ACTIVE_USERS_SQL, limit)]

async def audit(conn, limit, days, table):
    return [dict(i) for i in await conn.fetch(AUDIT_SQL, limit, days, table)]

async def refresh(conn):
    await conn.execute("SELECT refresh_reports()")