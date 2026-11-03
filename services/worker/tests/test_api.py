from fastapi.testclient import TestClient

from app.api import api


def test_healthz_returns_ok() -> None:
    res = TestClient(api).get("/internal/healthz")

    assert res.status_code == 200
    assert res.json() == {"status": "ok"}
