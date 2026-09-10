from pydantic import BaseModel, ConfigDict


class LoginRequest(BaseModel):
    username: str
    password: str


class UserResponse(BaseModel):
    id: int
    username: str
    role: str

    model_config = ConfigDict(from_attributes=True)


class VehicleCreate(BaseModel):
    plate: str


class VehicleResponse(BaseModel):
    id: int
    plate: str
    owner_id: int

    model_config = ConfigDict(from_attributes=True)