
LIST_SQL = """
    SELECT * FROM v_bookings_full
    WHERE ($1::booking_status IS NULL OR status = $1::booking_status)
        AND ($2::int IS NULL OR room_id = $2::int)
        AND ($3::timestamptz IS NULL OR end_at > $3::timestamptz)
        AND ($4::timestamptz IS NULL OR start_at < $4::timestamptz)
    ORDER BY start_at DESC
    LIMIT $5
"""

async def list_(conn, status, room_id, date_from, date_to, limit):
    rows = await  conn.fetch(LIST_SQL, status, room_id, date_from, date_to, limit)
    return [dict(i) for i in rows ]

async def get(conn, booking_id:int):
    row = await conn.fetchrow("SELECT v_bookings_full WHERE id = $1", booking_id)
    return dict(row) if row else None


async def create(conn, room_id, start, end, title):
    booking_id = await conn.fetchval("SELECT book_room($1,$2,$3,$4)", room_id, start, end, title)
    return await get(conn,booking_id)

async def cancel(conn, booking_id: int) -> bool:
    return await conn.fetchval("SELECT cancel_booking($1)", booking_id)


async def confirm(conn, booking_id: int) -> bool:
    return await conn.fetchval("SELECT confirm_booking($1)", booking_id)


