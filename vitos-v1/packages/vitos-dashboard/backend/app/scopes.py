"""Lab-scope manifest CRUD. Stub for SP5."""
from pathlib import Path

from fastapi import APIRouter, Depends

from .auth import current_admin

router = APIRouter()
SCOPE_DIR = Path("/etc/vitos/lab-scopes")


@router.get("")
def list_scopes(_admin: str = Depends(current_admin)) -> list[str]:
    if not SCOPE_DIR.exists():
        return []
    return sorted(p.name for p in SCOPE_DIR.glob("*.yaml"))


@router.post("/active")
def activate(body: dict, _admin: str = Depends(current_admin)) -> dict:
    return {"ok": True, "active": body.get("name")}
