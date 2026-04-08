"""Alerts SSE — verify the tail picks up new lines and is auth-gated."""
import json
import os
import sys
import tempfile
import time

import pytest
from fastapi.testclient import TestClient


@pytest.fixture
def client(monkeypatch):
    tmp = tempfile.mkdtemp()
    db = os.path.join(tmp, "sessions.db")
    log = os.path.join(tmp, "alerts.jsonl")
    open(log, "a").close()
    monkeypatch.setenv("VITOS_SESSION_DB", db)

    for mod in list(sys.modules):
        if mod.startswith("app."):
            sys.modules.pop(mod, None)

    from app import alerts as alerts_mod
    from app import auth as auth_mod
    from pathlib import Path
    monkeypatch.setattr(alerts_mod, "ALERT_LOG", Path(log))
    monkeypatch.setattr(auth_mod, "_pam_authenticate",
                        lambda u, p: (u, p) == ("alice", "secret"))
    monkeypatch.setattr(auth_mod, "_in_admin_group", lambda u: u == "alice")

    from app.main import app
    return TestClient(app), log


def test_alerts_unauthenticated_returns_401(client):
    c, _ = client
    r = c.get("/api/stream/alerts")
    assert r.status_code == 401


def test_alerts_stream_replays_existing_lines(client):
    c, log = client
    with open(log, "a") as fh:
        fh.write(json.dumps({"ts": "2026-04-08T00:00:00Z", "category": "Suspicious",
                             "score": 30, "student_id": "x"}) + "\n")
    c.post("/api/auth/login", json={"user": "alice", "pw": "secret"})
    with c.stream("GET", "/api/stream/alerts") as r:
        assert r.status_code == 200
        # Read enough bytes to capture the heartbeat + first event
        chunk = b""
        deadline = time.time() + 3
        for piece in r.iter_bytes():
            chunk += piece
            if b"Suspicious" in chunk or time.time() > deadline:
                break
        assert b"Suspicious" in chunk
