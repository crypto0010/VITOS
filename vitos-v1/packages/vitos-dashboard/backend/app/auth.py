"""PAM authentication + server-side session store.

Login: POST /api/auth/login {user, pw}
       Verifies credentials via PAM, requires the caller to be in the
       'vitos-admins' group, then issues a 32-byte hex session id stored
       in /var/lib/vitos/dashboard/sessions.db. The session id is set as
       an HttpOnly, SameSite=Strict cookie 'vitos_sid' valid for 8 h.

Logout: POST /api/auth/logout
        Deletes the row + clears the cookie.

Other modules import `current_admin` as a FastAPI dependency:
    @router.get("/protected")
    def thing(admin: str = Depends(current_admin)): ...
"""
from __future__ import annotations

import grp
import os
import secrets
import sqlite3
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

from fastapi import APIRouter, Cookie, Depends, HTTPException, Response, status
from pydantic import BaseModel

DEFAULT_DB_PATH = "/var/lib/vitos/dashboard/sessions.db"
SESSION_TTL = timedelta(hours=8)


def _db_path() -> Path:
    """Resolved on every call so tests can monkeypatch VITOS_SESSION_DB."""
    return Path(os.environ.get("VITOS_SESSION_DB", DEFAULT_DB_PATH))

COOKIE_NAME = "vitos_sid"
ADMIN_GROUP = "vitos-admins"

router = APIRouter()


class LoginBody(BaseModel):
    user: str
    pw: str


def _conn() -> sqlite3.Connection:
    p = _db_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    c = sqlite3.connect(p)
    c.execute(
        "CREATE TABLE IF NOT EXISTS sessions ("
        " sid TEXT PRIMARY KEY,"
        " user TEXT NOT NULL,"
        " created TEXT NOT NULL,"
        " expires TEXT NOT NULL)"
    )
    return c


def _in_admin_group(user: str) -> bool:
    try:
        return user in grp.getgrnam(ADMIN_GROUP).gr_mem
    except KeyError:
        return False


def _pam_authenticate(user: str, pw: str) -> bool:
    """Authenticate via PAM. Returns False on any failure including missing pam."""
    try:
        import pam  # python-pam
    except ImportError:
        return False
    p = pam.pam()
    return bool(p.authenticate(user, pw, service="login"))


def issue_session(user: str) -> str:
    sid = secrets.token_hex(32)
    now = datetime.now(timezone.utc)
    exp = now + SESSION_TTL
    with _conn() as c:
        c.execute(
            "INSERT INTO sessions (sid, user, created, expires) VALUES (?, ?, ?, ?)",
            (sid, user, now.isoformat(), exp.isoformat()),
        )
    return sid


def revoke_session(sid: str) -> None:
    with _conn() as c:
        c.execute("DELETE FROM sessions WHERE sid = ?", (sid,))


def lookup_session(sid: str) -> str | None:
    """Return the username for a valid, unexpired session id, else None."""
    if not sid:
        return None
    with _conn() as c:
        row = c.execute(
            "SELECT user, expires FROM sessions WHERE sid = ?", (sid,)
        ).fetchone()
    if not row:
        return None
    user, expires = row
    try:
        if datetime.fromisoformat(expires) < datetime.now(timezone.utc):
            revoke_session(sid)
            return None
    except ValueError:
        return None
    return user


# ---- routes ---------------------------------------------------------------


@router.post("/login")
def login(body: LoginBody, response: Response) -> dict:
    if not _pam_authenticate(body.user, body.pw):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="bad credentials")
    if not _in_admin_group(body.user):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="not in vitos-admins")
    sid = issue_session(body.user)
    response.set_cookie(
        key=COOKIE_NAME,
        value=sid,
        httponly=True,
        samesite="strict",
        secure=False,  # caddy terminates TLS in front; cookie is intra-host
        max_age=int(SESSION_TTL.total_seconds()),
        path="/",
    )
    return {"ok": True, "user": body.user}


@router.post("/logout")
def logout(response: Response, vitos_sid: str | None = Cookie(default=None)) -> dict:
    if vitos_sid:
        revoke_session(vitos_sid)
    response.delete_cookie(COOKIE_NAME, path="/")
    return {"ok": True}


@router.get("/me")
def me(vitos_sid: str | None = Cookie(default=None)) -> dict:
    user = lookup_session(vitos_sid or "")
    if not user:
        raise HTTPException(status_code=401, detail="not logged in")
    return {"user": user}


# ---- dependency for other routers ----------------------------------------


def current_admin(vitos_sid: str | None = Cookie(default=None)) -> str:
    user = lookup_session(vitos_sid or "")
    if not user:
        raise HTTPException(status_code=401, detail="not authenticated")
    return user
