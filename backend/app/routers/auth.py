from fastapi import APIRouter, Depends, Header, HTTPException
from .. import db
from ..deps import User, current_user, bearer_token
from ..schemas.models import RegisterIn, LogIn

router = APIRouter(prefix="/api/auth", tags=["auth"])


@router.post("/register", status_code=201)
async def register(data:RegisterIn):
   user_id = await db.pool.fetchval("SELECT register_user($1, $2, $3)", data.email, data.full_name, data.password) 
   return {"id": user_id}

@router.post("/login")
async def login(data:LogIn):
   row = await db.pool.fetchrow("SELECT * FROM login($1, $2)", data.email, data.password)
   return {
      "token": str(row["out_token"]),
      "user": {
         "id": row["out_id"], "name": row["out_name"], "role": row["out_role"]
      }
   }

@router.get("/me")
async def me(user: User = Depends(current_user)):
   return {"id": user.id, "name": user.name, "role": user.role}


@router.post("/logout", status_code=204)
async def logout(authorization:str | None = Header(default = None)):
   token = bearer_token(authorization)
   if token is None:
      raise HTTPException(401, "Нет токена")
   await db.pool.execute("SELECT logout($1)", token)