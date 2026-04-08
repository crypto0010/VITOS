"""Student roster — joins /run/vitos/sessions with the latest alert per student."""
from __future__ import annotations

import json
from pathlib import Path

from fastapi import APIRouter, Depends

from .auth import current_admin
from . import events as events_mod

router = APIRouter()

SESSION_DIR = Path("/run/vitos/sessions")
ALERT_LOG = Path("/var/log/vitos/alerts.jsonl")


def _latest_alert_per_student() -> dict[str, dict]:
    if not ALERT_LOG.exists():
        return {}
    out: dict[str, dict] = {}
    for line in ALERT_LOG.read_text().splitlines():
        try:
            a = json.loads(line)
        except json.JSONDecodeError:
            continue
        sid = a.get("student_id")
        if sid:
            out[sid] = a  # later lines overwrite — last wins
    return out


@router.get("")
def list_students(_admin: str = Depends(current_admin)) -> list[dict]:
    latest = _latest_alert_per_student()
    out: list[dict] = []
    seen: set[str] = set()
    if SESSION_DIR.exists():
        for child in sorted(SESSION_DIR.iterdir()):
            sid = child.name
            seen.add(sid)
            a = latest.get(sid, {})
            out.append({
                "id": sid,
                "risk": a.get("score", 0),
                "category": a.get("category", "Normal"),
                "ai_reason": a.get("ai_reason", ""),
            })
    # Also include students with alerts but no live session
    for sid, a in latest.items():
        if sid not in seen:
            out.append({
                "id": sid,
                "risk": a.get("score", 0),
                "category": a.get("category", "Normal"),
                "ai_reason": a.get("ai_reason", ""),
            })
    return out


@router.get("/{student_id}")
def student_detail(student_id: str, _admin: str = Depends(current_admin)) -> dict:
    latest = _latest_alert_per_student().get(student_id, {})
    return {
        "id": student_id,
        "risk": latest.get("score", 0),
        "category": latest.get("category", "Normal"),
        "events": events_mod.get_recent(student_id, 100),
        "latest_alert": latest,
    }
