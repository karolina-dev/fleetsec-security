from fastapi import APIRouter

from ..auth import create_access_token
from ..schemas import LoginRequest

router = APIRouter(prefix="/auth", tags=["Authentication"])


@router.post("/login")
def login(data: LoginRequest):
    if data.username == "admin" and data.password == "admin123":
        token = create_access_token({
            "sub": data.username,
            "role": "admin"
        })

        return {
            "access_token": token,
            "token_type": "bearer"
        }

    return {
        "error": "Invalid credentials"
    }