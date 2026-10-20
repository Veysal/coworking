from fastapi import APIRouter, Depends, Query
from ..deps import User, admin_user, get_conn
from ..repositories import reports as repo
from datetime import date, timedelta

router = APIRouter(prefix="/api/reports", tags=["reports"])

def _range(d1: date | None, d2: date | None):
    d2 = d2 or d2.today()
    return d1 or d2 - timedelta(days=29), d2

@router.get("/utilization")
async def utilization(
    date_from: date | None = Query(None, alias="from"),
    date_to: date | None = Query(None, alias="to"),
    limit: int = Query(30, ge=1, le=100),
    _: User = Depends(admin_user), conn = Depends(get_conn)
):
    d1, d2 = _range(date_from, date_to)
    return await repo.utilization(conn, d1, d2, limit)


@router.get("/daily")
async def daily(
    date_from: date | None = Query(None, alias="from"),
    date_to: date | None = Query(None, alias="to"),
    _: User = Depends(admin_user), conn = Depends(get_conn)
):
    d1, d2 = _range(date_from, date_to)
    return await repo.daily(conn, d1, d2)


@router.get("/top-users")
async def top_users(
    per_building: int = Query(5, ge=1, le=20),
    days: int = Query(90, ge=1, le=3650),
    _: User = Depends(admin_user), conn = Depends(get_conn)
):
    return await repo.top_users(conn, per_building, days)


@router.get("/summary")
async def summary(
    date_from: date | None = Query(None, alias="from"),
    date_to: date | None = Query(None, alias="to"),
    _: User = Depends(admin_user), conn = Depends(get_conn)
):
    d1, d2 = _range(date_from, date_to)
    return await repo.summary(conn, d1, d2)


@router.get("/active-user")
async def active_user(
    limit: int = Query(10, ge=1, le=100),
    _: User = Depends(admin_user), conn = Depends(get_conn)
):
    return await repo.active_users(conn, limit)


@router.get("/audit")
async def audit(
    limit: int = Query(50, ge=1, le=500),
    days: int = Query(30, ge=1, le=365),
    table: str | None = None,
    _: User = Depends(admin_user), conn = Depends(get_conn)
):
    return await repo.audit(conn, limit, days, table)


@router.post("/refresh", status_code=204)
async def refresh(_: User = Depends(admin_user), conn = Depends(get_conn)):
    await repo.refresh(conn)