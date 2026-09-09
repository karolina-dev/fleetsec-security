from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from ..auth import get_current_user
from ..database import get_db
from ..models import Vehicle
from ..schemas import VehicleCreate, VehicleResponse

router = APIRouter(prefix="/vehicles", tags=["Vehicles"])


@router.post("/", response_model=VehicleResponse)
def create_vehicle(
    data: VehicleCreate,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    vehicle = Vehicle(
        plate=data.plate,
        owner_id=1
    )

    db.add(vehicle)
    db.commit()
    db.refresh(vehicle)

    return vehicle