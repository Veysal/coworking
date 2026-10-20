import asyncio
import asyncpg

CHANNEL = "booking_events"

class Hub:
    def __init__(self):
        self.queues: set[asyncio.Queue] = set()
        self.conn: asyncpg.Connection | None = None

    async def start(self, dsn: str):
        for attempt in range(10):
            try:
                self.conn = await asyncpg.connect(dsn)
                await self.conn.add_listener(CHANNEL, self._on_notify)
                return
            except (asyncpg.PostgresConnectionError, OSError) as e:
                if attempt < 9:
                    asyncio.sleep(1)
                else:
                    raise
    async def stop(self):
        if self.conn:
            await self.conn.close()

    async def _on_notify(self, conn, pid, channel, payload:str):
        for q in list(self.queues):
            try:
                q.put_nowait(payload)
            except asyncio.QueueFull:
                pass

    async def stream(self):
        q: asyncio.Queue = asyncio.Queue(maxsize=100)
        self.queues.add(q)
        try:
            yield "retry: 3000\n\n"
            while True:
                try:    
                    payload = await asyncio.wait_for(q.get(), timeout=15)
                    yield f"data: {payload}\n\n"
                except asyncio.TimeoutError:
                    yield ": ping\n\n"
        finally:
            self.queues.discard(q)


hub = Hub()
