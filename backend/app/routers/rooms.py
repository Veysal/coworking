from fastapi import APIRouter, Depends, HTTPException, Query
from flet import Offset

from ..deps import User, admin_user, get_conn
from ..schemas.models import RoomIn, RoomOut, Slot
from ..repositories import rooms as repo
from ..config import DEFAULT_TZ

from datetime import date
from pydantic import AwareDatetime

router = APIRouter(prefix="/api", tags=["rooms"])

@router.get("/rooms", response_model=list[RoomOut])
async def list_rooms(
    q: str | None = Query(None, description="Search with trigrams"),
    min_capacity: int | None  = Query(None, ge=1),
    tags: str | None = None,
    equipment: str | None = Query(None, description="Use comma to seporate requests: printer, projector, ..."),
    location_id: int | None = None,
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    conn = Depends(get_conn)
):
    eq = {i.strip(): True for i in equipment.split(",") if i.strip()} if equipment else None
    return await repo.search(conn, q.strip() if q else None, min_capacity, tags, eq, location_id, limit, offset)


@router.get("/rooms/free")
async def free_room(
    start: AwareDatetime, end: AwareDatetime, min_capacity: int = Query(1,ge=1), conn= Depends(get_conn)
):
    if end <= start:
        raise HTTPException(400, "Конец интервала должен быть больше начала")
    return await repo.free_room(conn,start, end, min_capacity)


@router.get("/rooms/{room_id}", response_model=RoomOut)
async def get_room(room_id:int, conn = Depends(get_conn)):
    room = await repo.get(conn, room_id)
    if not room:
        raise HTTPException(404, "Комната не найдена")
    return room

@router.get("/rooms/{room_id}/availability", response_model=list[Slot])
async def availability(room_id:int, day: date = Query(alias="date"), tz:str = DEFAULT_TZ, conn = Depends(get_conn)):
    return await repo.availability(conn, room_id, day, tz)

@router.get("/locations/tree")
async def locations_tree(conn = Depends(get_conn)):
    return await repo.location_tree(conn)


@router.post("/rooms", response_model=RoomOut, status_code=201)
async def create_room(data: RoomIn, _: User = Depends(admin_user), conn = Depends(get_conn)):
    return await repo.create(conn,data.model_dump())


@router.put("/room/{room_id}", response_model=RoomOut)
async def update_room(room_id:int, data: RoomIn, _: User = Depends(admin_user), conn = Depends(get_conn)):
    room = await repo.update(conn, room_id, data.model_dump())
    if not room:
        raise HTTPException(404, "Комната не найдена")
    return room


@router.delete("/rooms/{room_id}", status_code = 204)
async def delete_room(room_id: int, _: User = Depends(admin_user), conn = Depends(get_conn)):
    if not await repo.deactivate(conn, room_id):
        raise HTTPException(404, "Комната не найдена")