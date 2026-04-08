"""Session control — shells out to vitosctl, all actions auth-gated and audited."""
from __future__ import annotations

import subprocess
from fastapi import APIRouter, Depends, HTTPException

from .auth import current_admin
from .audit import write as audit_write

router = APIRouter()


def _vitosctl(*args: str) -> str:
    try:
        return subprocess.check_output(["vitosctl", *args], text=True)
    except FileNotFoundError as e:
        raise HTTPException(status_code=500, detail=f"vitosctl missing: {e}")
    except subprocess.CalledProcessError as e:
        raise HTTPException(status_code=500, detail=f"vitosctl failed: {e}")


@router.get("")
def list_sessions(_admin: str = Depends(current_admin)) -> list[str]:
    return _vitosctl("session", "list").splitlines()


@router.post("/{session_id}/freeze")
def freeze(session_id: str, admin: str = Depends(current_admin)) -> dict:
    out = _vitosctl("session", "freeze", session_id)
    audit_write(admin, "freeze", session_id, "ok")
    return {"out": out}


@router.post("/{session_id}/isolate")
def isolate(session_id: str, admin: str = Depends(current_admin)) -> dict:
    out = _vitosctl("session", "isolate", session_id)
    audit_write(admin, "isolate", session_id, "ok")
    return {"out": out}


@router.post("/{session_id}/release")
def release(session_id: str, admin: str = Depends(current_admin)) -> dict:
    out = _vitosctl("session", "isolate", session_id, "--revert")
    audit_write(admin, "release", session_id, "ok")
    return {"out": out}
