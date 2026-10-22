import logging
from contextlib import asynccontextmanager

import asyncpg
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse

from . import db
from .config import DATABASE_URL
from .realtime import hub
from .routers import auth, bookings, reports, rooms

log = logging.getLogger("coworking")

@asynccontextmanager
async def lifespan(app: FastAPI):
    await db.start()
    await hub.start(DATABASE_URL)
    yield
    await db.stop
    await hub.stop()

app = FastAPI(title="СCoworking API", version="1.0.0", lifespan=lifespan)

app.include_router(auth.router)
app.include_router(rooms.router)
app.include_router(reports.router)
app.include_router(bookings.router)

CONSTRAINT_MESSAGES = {
    "bookings_no_overlap": "Это время уже занято",
    "users_email_uq": "Пользователь с таким email уже существует",
    "period_max_8h": "Бронь не может быть больше 8 часов",
    "period_is_bounded": "Некорректный период брони",
    "email_address_check": "Некорреткный emal адрес"
}


@app.exception_handler(asyncpg.PostgresError)
async def postgres_error_handler(request: Request, exc: asyncpg.PostgresError):
    code = getattr(exc, "sqlstate", "") or ""
    constraint = getattr(exc, "constraint_name", None)
    messages = CONSTRAINT_MESSAGES.get(constraint or "")
    if code == "23P01":
        status, detail = 409, messages or "Это время уже занято"
    elif code == "23505":
        status, detail = 409, messages or "Такая запись уже существует"
    elif code in ("23503", "23502", "23514", "23000"):
        status, detail = 422, messages or f"Некорректные данные ({exc.messages})"
    elif code == "42501":
        status, detail = 403, "Недостаточно прав"
        if "администратор" in exc.messages:
            detail = exc.messages
    elif code in ("28000", "28P01"):
            status, detail = 401, exc.messages
    elif code == "P0001":
            status, detail = 422, exc.messages
    else:
        log.exception("Необработанная ошибка в Postgres: %s", code)
        status, detail = 500, "Внутренняя ошибка базы данных"
    return JSONResponse({"detail": detail, "sqlstate": code, }, status_code=status)


@app.get("/api/events", tags=["realtime"])
async def events():
     return StreamingResponse(
          hub.stream(), media_type="text/event-stream",
          headers={"Cache-Control":"no-cache", "X-Accel-Buffering": "no"}
     )


@app.get("/api/health", tags=["service"])
async def health():
     return {"status": "ok", "postgres": await db.pool.fetchval('SHOW server-version')}