import uuid
from dataclasses import dataclass
from fastapi import Depends, Header, HTTPException
from . import db


@dataclass
class User:
    id: int
    name: str
    role: str

# JWT токен
def bearer_token(authorization:str | None) ->uuid.UUID | None:
    if not authorization or not authorization.lower().startswith("bearer "):
        return None
    try:
        return uuid.UUID(authorization[7:].strip())
    except ValueError:
        return None

async def optional_user(authorization: str | None = Header(default=None)) -> User | None:
    token = bearer_token(authorization)
    if token is None:
        return None
    row = await db.pool.fetchrow("SELECT * FROM auth_user($1)", token)
    return User(row['out_id'],row['out_name'],row['out_role']) if row else None


async def current_user(user:User | None = Depends(optional_user)) -> User:
    if user is None:
        raise HTTPException(401, "Требуется вход в систему")
    return user

async def admin_user(user: User | None = Depends(current_user)) -> User:
    if user.role != 'admin':
        raise HTTPException(403, "Доступ только для админа")
    return user


async def get_conn(user:User | None = Depends(optional_user)):
    async with db.pool.acquire() as conn:
        async with conn.transaction():
            await conn.execute(
                "SELECT set_config('app.user_id', $1, true), set_config('app.role', $2, true)",
               str(user.id) if user else "",
               user.role if user else "anonymous" 
            )
            yield conn