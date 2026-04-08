"""ttyd reverse-proxy. Stub for SP5 Task 8."""
from fastapi import APIRouter, HTTPException

router = APIRouter()


@router.get("/{session_id}/ws")
def term_ws(session_id: str) -> dict:
    raise HTTPException(status_code=501, detail="ttyd proxy not implemented yet (SP5 Task 8)")
