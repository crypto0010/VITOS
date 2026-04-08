"""Admin audit log writer + viewer."""
import json
import time
from pathlib import Path

from fastapi import APIRouter, Depends

from .auth import current_admin

AUDIT_LOG = Path("/var/log/vitos/dashboard-audit.jsonl")

router = APIRouter()


def write(admin: str, action: str, target: str, result: str) -> None:
    AUDIT_LOG.parent.mkdir(parents=True, exist_ok=True)
    entry = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "admin": admin,
        "action": action,
        "target": target,
        "result": result,
    }
    with AUDIT_LOG.open("a") as fh:
        fh.write(json.dumps(entry) + "\n")


@router.get("")
def tail(limit: int = 100, _admin: str = Depends(current_admin)) -> list[dict]:
    if not AUDIT_LOG.exists():
        return []
    lines = AUDIT_LOG.read_text().splitlines()[-limit:]
    out = []
    for line in lines:
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return out
