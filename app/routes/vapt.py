from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.orm import Session
from ..auth import SECRET_KEY, ALGORITHM
import ipaddress
import socket
from urllib.parse import urlparse
import jwt
import httpx

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

# V03 - SSRF
# Remediated version: only HTTPS URLs to an explicit allowlist are permitted.
ALLOWED_SSRF_HOSTS = {
    "example.com",
}

def is_private_or_local_host(hostname: str) -> bool:
    try:
        ip = ipaddress.ip_address(hostname)
        return (
            ip.is_private
            or ip.is_loopback
            or ip.is_link_local
            or ip.is_reserved
        )
    except ValueError:
        try:
            addresses = socket.getaddrinfo(
                hostname,
                None,
                type=socket.SOCK_STREAM,
            )

            for address in addresses:
                ip = ipaddress.ip_address(address[4][0])

                if (
                    ip.is_private
                    or ip.is_loopback
                    or ip.is_link_local
                    or ip.is_reserved
                ):
                    return True

        except socket.gaierror:
            return True

    return False


@router.get("/v03/fetch")
def v03_fetch_url(url: str):
    parsed = urlparse(url)

    if parsed.scheme != "https":
        return {
            "error": "Solo se permiten URLs HTTPS"
        }

    if not parsed.hostname:
        return {
            "error": "URL inválida"
        }

    hostname = parsed.hostname.lower()

    if hostname not in ALLOWED_SSRF_HOSTS:
        return {
            "error": "Host no permitido"
        }

    if is_private_or_local_host(hostname):
        return {
            "error": "El acceso a hosts privados o locales está bloqueado"
        }

    try:
        response = httpx.get(
            url,
            timeout=5.0,
            follow_redirects=False,
        )

        return {
            "status_code": response.status_code,
            "content_type": response.headers.get("content-type"),
            "body": response.text[:2000],
        }

    except Exception:
        return {
            "error": "No fue posible consultar el recurso"
        }