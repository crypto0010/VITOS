"""Auth tests — mock PAM and group lookup so unit tests don't need a real PAM stack."""
import os
import sys
import tempfile

import pytest
from fastapi.testclient import TestClient


@pytest.fixture
def client(monkeypatch):
    # Use a per-test sessions DB
    tmp = tempfile.mkdtemp()
    db = os.path.join(tmp, "sessions.db")
    monkeypatch.setenv("VITOS_SESSION_DB", db)

    # Re-import to pick up the env var
    for mod in list(sys.modules):
        if mod.startswith("app."):
            sys.modules.pop(mod, None)

    from app import auth as auth_mod
    from app.main import app

    monkeypatch.setattr(auth_mod, "_pam_authenticate",
                        lambda u, p: (u, p) == ("alice", "secret"))
    monkeypatch.setattr(auth_mod, "_in_admin_group",
                        lambda u: u == "alice")
    return TestClient(app)


def test_login_bad_credentials(client):
    r = client.post("/api/auth/login", json={"user": "alice", "pw": "wrong"})
    assert r.status_code == 401


def test_login_good_credentials_not_admin_forbidden(client, monkeypatch):
    from app import auth as auth_mod
    monkeypatch.setattr(auth_mod, "_in_admin_group", lambda u: False)
    r = client.post("/api/auth/login", json={"user": "alice", "pw": "secret"})
    assert r.status_code == 403


def test_login_success_sets_cookie(client):
    r = client.post("/api/auth/login", json={"user": "alice", "pw": "secret"})
    assert r.status_code == 200
    assert r.json() == {"ok": True, "user": "alice"}
    assert "vitos_sid" in r.cookies


def test_me_after_login(client):
    client.post("/api/auth/login", json={"user": "alice", "pw": "secret"})
    r = client.get("/api/auth/me")
    assert r.status_code == 200
    assert r.json()["user"] == "alice"


def test_me_without_login(client):
    r = client.get("/api/auth/me")
    assert r.status_code == 401


def test_logout_clears_session(client):
    client.post("/api/auth/login", json={"user": "alice", "pw": "secret"})
    r = client.post("/api/auth/logout")
    assert r.status_code == 200
    r2 = client.get("/api/auth/me")
    assert r2.status_code == 401
