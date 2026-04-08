"""Alert log tail + SSE. Stub for SP5 Task 4."""
import asyncio
import json
import os
from pathlib import Path

from fastapi import APIRouter
from fastapi.responses import StreamingResponse

ALERT_LOG = Path("/var/log/vitos/alerts.jsonl")

router = APIRouter()


async def _tail() -> "asyncio.AsyncIterator[bytes]":
    """Yield SSE-formatted alert lines as they appear in alerts.jsonl."""
    yield b": vitos heartbeat\n\n"
    if not ALERT_LOG.exists():
        ALERT_LOG.parent.mkdir(parents=True, exist_ok=True)
        ALERT_LOG.touch()
    with ALERT_LOG.open("rb") as fh:
        fh.seek(0, os.SEEK_END)
        while True:
            line = fh.readline()
            if not line:
                await asyncio.sleep(0.5)
                continue
            try:
                json.loads(line)
            except json.JSONDecodeError:
                continue
            yield b"data: " + line.rstrip(b"\n") + b"\n\n"


@router.get("/alerts")
async def stream_alerts() -> StreamingResponse:
    return StreamingResponse(_tail(), media_type="text/event-stream")
