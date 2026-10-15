""" Полнотекстовый поиск + триграмма + JSONB + массивы + рекурсивный CTE """

ROOM_COLS = """
    r.id, r.name, r.capacity, r.price_per_hour::float AS price_per_hour, r.tags,
    r.equipment, r.description, r.location_id, r.is_active, r.place
"""


SEARCH_SQL = f"""
    WITH RECURSIVE sub AS (
        SELECT id FROM locations WHERE id = $5::int
        UNION ALL
        SELECT l.id FROM locations l JOIN sub ON l.parent_id = sub.id
    ), s AS (
        SELECT CASE WHEN $1::text IS NULL THEN NULL
            ELSE websearch_to_tsquery('russian', $1::text) END AS tsq
    )
    SELECT {ROOM_COLS},
        CASE WHEN $1::text IS NULL THEN 0
            ELSE ts_rank(r.search_vec, s.tsq) + similarity(r.name, $1::text) END AS score,
        CASE WHEN s.tsq IS NULL THEN NULL
            ELSE ts_headline('russian', coalesce(r.description, ''), s.tsq,
                'MaxFragments=1, MaxWords=18, MinWords=5') END AS headline,
        count(*) Over () AS total_count
    FROM rooms r
    JOIN v_room_places p ON p.room_id = r.id
    CROSS JOIN s
    WHERE r.is_active
        AND ($1::text IS NULL OR r.search_vec @@ s.tsq
        OR r.name % $1::text OR r.name ILIKE '%' || $1::text || '%')
        AND ($2::int IS NULL OR r.capacity >= $2::int)
        AND ($3::text IS NULL OR r.tags @> ARRAY[$3::text])
        AND ($4::jsonb IS NULL OR r.equipment @> $4::jsonb)
        AND ($5::int IS NULL OR r.location_id IN (SELECT id FROM sub))
    ORDER BY score DESC, r.name
    LIMIT $6 OFFSET $7
"""

async def search(conn, q, min_capacity, tag, equipment, location_id, limit, offset):
    await conn.execute("SELECT set_config('pg_trgm.similarity_threshold', '0.2', true)")
    rows = await conn.fetch(
        SEARCH_SQL,q or None,min_capacity,tag or None,equipment or None,location_id,limit,offset
    )
    return [dict(i) for i in rows]

async def get(conn, room_id:int):
    row = await conn.fetch(
        f"SELECT {ROOM_COLS} FROM rooms r JOIN v_room_places p ON p.room_id = r.id WHERE r.id = $1", room_id)
    return dict(row) if row else None


async def create(conn, d: dict):
    rid = await conn.fetchval("""
        INSERT INTO rooms (location_id, name, capacity, price_per_hour, tags, equipment, description)
        VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id""",
        d["location_id"], d["name"], d["capacity"], d["price_per_hour"], d["tags"], d["equipment"], d["description"])
    return await get(conn,rid)

async def update(conn, room_id: int, d:dict):
    rid = await conn.fetchval("""
        UPDATE rooms SET location_id=$2, name=$3, capacity=$4, price_per_hour=$5, tags=$6,
            equipment=$7, description=$8
        WHERE id = $1 RETURNING id""",
        room_id,d["location_id"], d["name"], d["capacity"], d["price_per_hour"], d["tags"], d["equipment"], d["description"])
    return await get(conn, rid)

async def deactivate(conn, room_id: int) -> bool:
    return await conn.fetchval("UPDATE rooms SET is_active=false WHERE id = $1 RETURNING true", room_id) is True

async def availability(conn, room_id: int, day, tz: str):
    rows = await conn.fetch("SELECT slot_start, slot_end, is_free FROM find_free_slots($1, $2, $3)",room_id, day, tz)
    return [dict(i) for i in rows ]


async def free_room(conn, start, end, min_capacity: int):
    rows = await conn.fetch(
        """
            SELECT o_room_id AS id, o_name AS name, o_place AS place, o_capacity AS capacity,
                o_price::float AS price_per_hour, o_next_at AS next_booking_at 
            FROM free_rooms($1, $2, $3) 
        """, start, end, min_capacity
    )
    return [dict(i) for i in rows]

async def location_tree(conn):
    rows = await conn.fetch(
        """
            WITH RECURSIVE t AS (
                SELECT id, parent_id, name, kind, 0 AS depth, ARRAY[name] AS path
                FROM locations WHERE parent_id IS NULL
                UNION ALL
                SELECT l.id, l.parent_id, l.name, l.kind, t.depth + 1, t.path || l.name
                FROM locations l JOIN t ON l.parent_id = t.id
            )
            SELECT t.id, t.parent_id, t.name, t.kind::text AS kind, t.depth,
                array_to_string(t.path, ' / ') AS full_path,
                (SELECT count(*)::int FROM rooms r WHERE r.location_id = t.id AND r.is_active) AS rooms_count
            FROM t ORDER BY t.path
        """
    )
    return [dict(i) for i in rows] 


