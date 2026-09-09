from fastapi import APIRouter, Depends

from ..auth import get_current_user

router = APIRouter(prefix="/users", tags=["Users"])


@router.get("/me")
def get_me(current_user: dict = Depends(get_current_user)):
    return {
        "username": current_user["username"],
        "role": current_user["role"]
    }