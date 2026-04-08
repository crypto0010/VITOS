"""Alerts SSE endpoint — verify it's auth-gated.

Note: we deliberately do NOT iterate the response body. FastAPI's
TestClient buffers streaming responses and the alerts.py tail loop
runs forever, so any attempt to read the body would hang. The unit
test scope is: 'is the endpoint registered, does it require auth,
does it return text/event-stream'. End-to-end SSE behavior is
exercised by the in-guest smoke test (dashboard_sse_gated) instead.
"""
import os
import sys
import tempfile

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
    return TestClient(app)


def test_alerts_unauthenticated_returns_401(client):
    r = client.get("/api/stream/alerts")
    assert r.status_code == 401
