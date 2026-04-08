"""Alert log tail + SSE.

Tails /var/log/vitos/alerts.jsonl and pushes new lines to subscribers as
SSE events. Sends a heartbeat comment every 15 s so proxies don't time
out the connection. Auth-gated via current_admin.
"""
from __future__ import annotations

import asyncio
import json
import os
from pathlib import Path

from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse

from .auth import current_admin

ALERT_LOG = Path("/var/log/vitos/alerts.jsonl")

router = APIRouter()


async def _tail():
    """Yield raw bytes for SSE clients."""
    yield b": vitos alerts stream\n\n"
    ALERT_LOG.parent.mkdir(parents=True, exist_ok=True)
    if not ALERT_LOG.exists():
        ALERT_LOG.touch()

    with ALERT_LOG.open("rb") as fh:
        # Replay last ~50 lines so reconnecting clients have context.
        fh.seek(0, os.SEEK_END)
        size = fh.tell()
        backbuf = 8192
        fh.seek(max(0, size - backbuf))
        tail_bytes = fh.read()
        for line in tail_bytes.splitlines()[-50:]:
            if line.strip():
                yield b"data: " + line + b"\n\n"
        # Now follow.
        last_heartbeat = asyncio.get_event_loop().time()
        while True:
            line = fh.readline()
            if line:
                try:
                    json.loads(line)
                except json.JSONDecodeError:
                    continue
                yield b"data: " + line.rstrip(b"\n") + b"\n\n"
                continue
            await asyncio.sleep(0.5)
            now = asyncio.get_event_loop().time()
            if now - last_heartbeat > 15:
                yield b": heartbeat\n\n"
                last_heartbeat = now


@router.get("/alerts")
async def stream_alerts(_admin: str = Depends(current_admin)) -> StreamingResponse:
    return StreamingResponse(_tail(), media_type="text/event-stream")
