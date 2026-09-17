from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.orm import Session
from ..auth import SECRET_KEY, ALGORITHM
import jwt

from ..database import get_db


router = APIRouter(prefix="/vapt", tags=["VAPT"])


# =========================================================
# V01 - SQL Injection
# =========================================================
# Remediated version using a parameterized query.
@router.get("/v01/vehicles")
def v01_search_vehicles(
    plate: str,
    db: Session = Depends(get_db),
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

# V02 - JWT alg:none
# Remediated version: signature and algorithm are explicitly validated.
@router.get("/v02/verify")
def v02_verify_token(token: str):
    try:
        payload = jwt.decode(
            token,
            SECRET_KEY,
            algorithms=[ALGORITHM],
        )

        header = jwt.get_unverified_header(token)

        return {
            "valid": True,
            "algorithm": header.get("alg"),
            "payload": payload,
        }

    except jwt.PyJWTError:
        return {
            "valid": False,
            "detail": "Token inválido o firma no válida",
        }