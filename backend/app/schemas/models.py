from datetime import datetime
from typing import Any
from pydantic import AwareDatetime, BaseModel, Field

class RegisterIn(BaseModel):
    email: str
    full_name: str = Field(min_length=2, max_length=100)
    password: str = Field(min_length=6, max_length=100)


class LogIn(BaseModel):
    email: str
    password: str

class RoomIn(BaseModel):
    location_id: int
    name: str = Field(min_length=2, max_length=100)
    capacity: int = Field(ge=0, le=100)
    price_per_hour: float = Field(ge=0, default=0)
    tags:list[str] = []
    equipment:dict[str, Any] = {}
    description: str | None = None

class RoomOut(BaseModel):
    id: int
    name: str
    capacity: int
    price_per_hour: float
    tags:list[str]
    equipment:dict[str, Any]
    description: str | None = None
    location_id: int
    place: str
    is_active: bool = True
    score: float | None = None
    headline: float | None = None
    total_count: int | None = None

class BookingIn(BaseModel):
    room_id: int
    start: AwareDatetime
    end: AwareDatetime
    title: str = Field(default="Встреча", max_length=200)

class BookingOut(BaseModel):
    id: int
    room_id: int
    room_name: str
    place: str
    user_id: int
    user_name: str
    start_at: datetime
    end_at: datetime
    duration_min: int
    status: str
    title: str
    created_at: datetime


class Slot(BaseModel):
    slot_start: datetime
    slot_end: datetime
    is_free: bool
