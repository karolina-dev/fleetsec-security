from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.orm import Session

from ..auth import get_current_user
from ..database import get_db

router = APIRouter(prefix="/vapt", tags=["VAPT"])


# V01 - SQL Injection
# Remediated version using a parameterized query.
@router.get("/v01/vehicles")
def v01_search_vehicles(
    plate: str,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    query = text(
        """
        SELECT id, plate, owner_id
        FROM vehicles
        WHERE plate = :plate
        """
    )

    result = db.execute(
        query,
        {"plate": plate},
    )

    rows = result.mappings().all()

    return {
        "results": [dict(row) for row in rows]
    }