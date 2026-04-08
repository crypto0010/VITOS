"""Student roster. Stub for SP5 — returns the contents of /run/vitos/sessions/."""
from pathlib import Path

from fastapi import APIRouter

router = APIRouter()

SESSION_DIR = Path("/run/vitos/sessions")


@router.get("")
def list_students() -> list[dict]:
    if not SESSION_DIR.exists():
        return []
    out = []
    for child in sorted(SESSION_DIR.iterdir()):
        out.append({"id": child.name, "risk": 0, "category": "Normal"})
    return out


@router.get("/{student_id}")
def student_detail(student_id: str) -> dict:
    return {"id": student_id, "risk": 0, "events": [], "alerts": []}
