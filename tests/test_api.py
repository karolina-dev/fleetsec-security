import os

os.environ.setdefault(
    "FLEETSEC_SECRET_KEY",
    "fleetsec-dev-secret-key-2026-change-me"
)

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
            "username": "admin",
            "password": "admin123"
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
            "username": "admin",
            "password": "admin123"
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
        "username": "admin",
        "role": "admin"
    }