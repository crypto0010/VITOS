"""PAM authentication. Stub for SP5 Task 3 — login currently 501."""
from fastapi import APIRouter, HTTPException

router = APIRouter()


@router.post("/login")
def login() -> dict:
    raise HTTPException(status_code=501, detail="auth not implemented yet (SP5 Task 3)")


@router.post("/logout")
def logout() -> dict:
    return {"ok": True}
