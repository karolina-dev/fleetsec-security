import os

from fastapi import APIRouter

from ..auth import create_access_token
from ..schemas import LoginRequest

router = APIRouter(prefix="/auth", tags=["Authentication"])

ADMIN_USERNAME = os.getenv("FLEETSEC_ADMIN_USERNAME")
ADMIN_PASSWORD = os.getenv("FLEETSEC_ADMIN_PASSWORD")

if not ADMIN_USERNAME or not ADMIN_PASSWORD:
    raise RuntimeError(
        "FLEETSEC_ADMIN_USERNAME y FLEETSEC_ADMIN_PASSWORD deben estar configuradas"
    )


@router.post("/login")
def login(data: LoginRequest):
    if (
        data.username == ADMIN_USERNAME
        and data.password == ADMIN_PASSWORD
    ):
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