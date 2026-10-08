import json
import asyncpg

from .config import DATABASE_URL

pool:asyncpg.Pool | None = None

async def _init_connection(conn: asyncpg.Connection) -> None:
    for typ in ("jsonb", "json"):
        await conn.set_type_codec(typ, encoder=json.dumps, decoder=json.loads, schema="pg_catalog")

async def start() -> None:
    global pool
    pool = await asyncpg.create_pool(
        DATABASE_URL,min_size=2, max_size=10, init=_init_connection
    )

async def stop() -> None:
    if pool:
        await pool.close()