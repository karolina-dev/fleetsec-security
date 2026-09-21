from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.orm import Session
from ..auth import SECRET_KEY, ALGORITHM
import ipaddress
import socket
from urllib.parse import urlparse
import jwt
import httpx
from lxml import etree
from ..models import User
from pathlib import Path
import time
from collections import defaultdict, deque

from fastapi import HTTPException, Request

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

# V04 - XXE
# Remediated version: external entities and DTD processing are disabled.
@router.post("/v04/xml")
def v04_parse_xml(xml: str):
    try:
        parser = etree.XMLParser(
            resolve_entities=False,
            load_dtd=False,
            no_network=True,
        )

        root = etree.fromstring(
            xml.encode("utf-8"),
            parser,
        )

        return {
            "valid": True,
            "content": etree.tostring(
                root,
                encoding="unicode",
            ),
        }

    except Exception:
        return {
        "valid": False,
        "error": "XML inválido o no permitido",
    }

# V05 - Mass Assignment
# Remediated version: only explicitly allowed fields can be updated.
@router.put("/v05/users/{username}")
def v05_update_user(
    username: str,
    data: dict,
    db: Session = Depends(get_db),
):
    user = db.query(User).filter(User.username == username).first()

    if not user:
        return {
            "error": "Usuario no encontrado"
        }

    allowed_fields = {"username"}

    for field in allowed_fields:
        if field in data:
            setattr(user, field, data[field])

    db.commit()
    db.refresh(user)

    return {
        "id": user.id,
        "username": user.username,
        "role": user.role,
    }

# V06 - Path Traversal
# Remediated version: resolved path must remain inside the allowed directory.
@router.get("/v06/file")
def v06_read_file(filename: str):
    base_dir = Path("vapt_files").resolve()

    try:
        file_path = (base_dir / filename).resolve()

        if file_path != base_dir and base_dir not in file_path.parents:
            return {
                "error": "Acceso al archivo no permitido"
            }

        if not file_path.is_file():
            return {
                "error": "Archivo no encontrado"
            }

        with open(file_path, "r", encoding="utf-8") as file:
            content = file.read()

        return {
            "filename": filename,
            "content": content,
        }

    except Exception:
        return {
            "error": "No fue posible leer el archivo"
        }

# V07 - Missing Rate Limiting
# Remediated version: 5 requests per minute per client.
RATE_LIMIT = 5
RATE_WINDOW = 60

request_history = defaultdict(deque)


@router.get("/v07/search")
def v07_search(q: str, request: Request):
    client_ip = request.client.host if request.client else "unknown"
    now = time.monotonic()

    history = request_history[client_ip]

    while history and now - history[0] > RATE_WINDOW:
        history.popleft()

    if len(history) >= RATE_LIMIT:
        raise HTTPException(
            status_code=429,
            detail="Límite de solicitudes excedido. Intente nuevamente más tarde.",
            headers={"Retry-After": str(RATE_WINDOW)},
        )

    history.append(now)

    return {
        "query": q,
        "results": [
            {
                "id": 1,
                "vehicle": "ABC123",
            }
        ],
    }