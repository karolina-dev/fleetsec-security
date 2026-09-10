import os

os.environ.setdefault(
    "FLEETSEC_SECRET_KEY",
    "fleetsec-dev-secret-key-2026-change-me"
)

if not os.getenv("FLEETSEC_ADMIN_USERNAME"):
    os.environ["FLEETSEC_ADMIN_USERNAME"] = "admin"

if not os.getenv("FLEETSEC_ADMIN_PASSWORD"):
    os.environ["FLEETSEC_ADMIN_PASSWORD"] = "fleetsec-test-password"

from fastapi.testclient import TestClient

from app.main import app


client = TestClient(app)


def test_health():
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "service": "fleetsec-api"
    }


def test_login():
    response = client.post(
        "/auth/login",
        json={
            "username": os.environ["FLEETSEC_ADMIN_USERNAME"],
            "password": os.environ["FLEETSEC_ADMIN_PASSWORD"]
        }
    )

    assert response.status_code == 200

    data = response.json()

    assert "access_token" in data
    assert data["token_type"] == "bearer"


def test_get_current_user():
    login_response = client.post(
        "/auth/login",
        json={
            "username": os.environ["FLEETSEC_ADMIN_USERNAME"],
            "password": os.environ["FLEETSEC_ADMIN_PASSWORD"]
        }
    )

    token = login_response.json()["access_token"]

    response = client.get(
        "/users/me",
        headers={
            "Authorization": f"Bearer {token}"
        }
    )

    assert response.status_code == 200
    assert response.json() == {
        "username": os.environ["FLEETSEC_ADMIN_USERNAME"],
        "role": "admin"
    }