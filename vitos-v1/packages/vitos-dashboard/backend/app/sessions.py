"""Session control — shells out to vitosctl. Stub bodies for SP5 Task 6."""
import subprocess
from fastapi import APIRouter, HTTPException

router = APIRouter()


def _vitosctl(*args: str) -> str:
    try:
        return subprocess.check_output(["vitosctl", *args], text=True)
    except (FileNotFoundError, subprocess.CalledProcessError) as e:
        raise HTTPException(status_code=500, detail=f"vitosctl error: {e}")


@router.get("")
def list_sessions() -> list[str]:
    return _vitosctl("session", "list").splitlines()


@router.post("/{session_id}/freeze")
def freeze(session_id: str) -> dict:
    return {"out": _vitosctl("session", "freeze", session_id)}


@router.post("/{session_id}/isolate")
def isolate(session_id: str) -> dict:
    return {"out": _vitosctl("session", "isolate", session_id)}


@router.post("/{session_id}/release")
def release(session_id: str) -> dict:
    return {"out": _vitosctl("session", "isolate", session_id, "--revert")}
