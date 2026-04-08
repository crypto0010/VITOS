"""VITOS admin dashboard — FastAPI app entry point."""
from __future__ import annotations

import time
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from . import __version__
from . import alerts as alerts_mod
from . import auth as auth_mod
from . import sessions as sessions_mod
from . import students as students_mod
from . import reports as reports_mod
from . import scopes as scopes_mod
from . import audit as audit_mod
from . import ttyd_proxy as ttyd_mod

START_TS = time.time()
WEB_DIR = Path("/usr/share/vitos/dashboard/web")

app = FastAPI(title="VITOS Admin", version=__version__)

# REST routers (each module exposes a router named `router`)
app.include_router(auth_mod.router,    prefix="/api/auth",     tags=["auth"])
app.include_router(students_mod.router, prefix="/api/students", tags=["students"])
app.include_router(sessions_mod.router, prefix="/api/sessions", tags=["sessions"])
app.include_router(reports_mod.router,  prefix="/api/sessions", tags=["reports"])
app.include_router(scopes_mod.router,   prefix="/api/scopes",   tags=["scopes"])
app.include_router(alerts_mod.router,   prefix="/api/stream",   tags=["stream"])
app.include_router(audit_mod.router,    prefix="/api/audit",    tags=["audit"])
app.include_router(ttyd_mod.router,     prefix="/api/term",     tags=["term"])


@app.get("/api/health")
def health() -> dict:
    return {
        "ok": True,
        "version": __version__,
        "uptime": int(time.time() - START_TS),
    }


# Static SPA — must be mounted *last* so it doesn't shadow /api/*.
if WEB_DIR.exists():
    app.mount("/assets", StaticFiles(directory=WEB_DIR / "assets"), name="assets")

    @app.get("/{path:path}", include_in_schema=False)
    def spa_fallback(path: str) -> FileResponse:
        # Any non-/api/ route returns index.html for client-side routing.
        return FileResponse(WEB_DIR / "index.html")
