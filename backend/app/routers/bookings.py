from fastapi import APIRouter, Depends, HTTPException, Query
from ..deps import User, current_user, get_conn
from ..schemas.models import BookingIn, BookingOut
from datetime import date, datetime, time, timedelta, timezone
from typing import Literal
from ..repositories import bookings as repo

router = APIRouter(prefix="/api/bookings", tags=["bookings"])

@router.get("", response_model = list[BookingOut])
async def list_bookings(
    status: Literal["pending", "confirmed", "cancelled"],
    room_id: int | None = None,
    date_from: date | None = None,
    date_to: date | None = None,
    limit: int = Query(100, ge=1, le=250),
    _: User = Depends(current_user),
    conn = Depends(get_conn)
):
    d_from = datetime.combine(date_from, time.min, timezone.utc) if date_from else None
    d_to = datetime.combine(date_to + timedelta(days=1), time.min, timezone.utc) if date_to else None
    return await repo.list_(conn, status, room_id, d_from, d_to, limit)

@router.post("", response_model=BookingOut, status_code=201)
async def create_booking(data:BookingIn, _: User = Depends(current_user),conn = Depends(get_conn)):
    return await repo.create(conn, data.room_id, data.start, data.end, data.title)


@router.delete("/{booking_id}", response_model=BookingOut, status_code=204)
async def cancel_booking(booking_id:int, _: User = Depends(current_user),conn = Depends(get_conn)):
    if not await repo.cancel(conn, booking_id):
        raise HTTPException(404, "Бронь не найдена или уже отменена")

@router.post("/{booking_id}/confirm", response_model=BookingOut)
async def confirm_booking(booking_id, _: User = Depends(current_user),conn = Depends(get_conn)):
    if not await repo.confirm(conn, booking_id):
        raise HTTPException(404, "Бронь не найдена или уже подтверждена")
    return await repo.get(conn, booking_id)