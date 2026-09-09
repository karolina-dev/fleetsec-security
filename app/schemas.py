from pydantic import BaseModel


class LoginRequest(BaseModel):
    username: str
    password: str


class UserResponse(BaseModel):
    id: int
    username: str
    role: str

    class Config:
        from_attributes = True


class VehicleCreate(BaseModel):
    plate: str


class VehicleResponse(BaseModel):
    id: int
    plate: str
    owner_id: int

    class Config:
        from_attributes = True