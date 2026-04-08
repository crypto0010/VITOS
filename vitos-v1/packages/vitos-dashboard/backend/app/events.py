"""vitos-busd subscriber + per-student ring buffer + SSE fan-out.

The subscriber runs as a background asyncio task, started during FastAPI
startup, that connects to /run/vitos/bus.sock.sub and parses one JSON
event per line. Each event is appended to:
  * a per-student deque (max 1000 events) for /api/students/{id}/events
  * a per-student asyncio.Queue list for /api/stream/events?student=<id>
"""
from __future__ import annotations

import asyncio
import json
from collections import defaultdict, deque
from pathlib import Path
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse

from .auth import current_admin

BUS_SUB = Path("/run/vitos/bus.sock.sub")
RING_SIZE = 1000

_rings: dict[str, deque] = defaultdict(lambda: deque(maxlen=RING_SIZE))
_subscribers: dict[str, list[asyncio.Queue]] = defaultdict(list)
_lock = asyncio.Lock()
_task: asyncio.Task | None = None

router = APIRouter()


async def _bus_loop() -> None:
    """Reconnect-forever loop reading newline-delimited JSON from the bus."""
    while True:
        if not BUS_SUB.exists():
            await asyncio.sleep(2)
            continue
        try:
            reader, _writer = await asyncio.open_unix_connection(str(BUS_SUB))
        except (FileNotFoundError, ConnectionRefusedError, OSError):
            await asyncio.sleep(2)
            continue
        try:
            while True:
                line = await reader.readline()
                if not line:
                    break
                try:
                    ev: dict[str, Any] = json.loads(line)
                except json.JSONDecodeError:
                    continue
                sid = ev.get("student_id")
                if not sid:
                    continue
                async with _lock:
                    _rings[sid].append(ev)
                    for q in _subscribers.get(sid, []):
                        try:
                            q.put_nowait(ev)
                        except asyncio.QueueFull:
                            pass
        except (ConnectionResetError, OSError):
            pass
        await asyncio.sleep(1)


def start_bus_task(loop: asyncio.AbstractEventLoop | None = None) -> None:
    """Idempotent — call from FastAPI startup."""
    global _task
    if _task is None or _task.done():
        loop = loop or asyncio.get_event_loop()
        _task = loop.create_task(_bus_loop())


def get_recent(student_id: str, limit: int = 100) -> list[dict]:
    return list(_rings.get(student_id, deque()))[-limit:]


# ---- routes ---------------------------------------------------------------


@router.get("")
def list_buffered_students(_admin: str = Depends(current_admin)) -> list[str]:
    return sorted(_rings.keys())


@router.get("/{student_id}")
def student_events(
    student_id: str,
    limit: int = Query(100, ge=1, le=RING_SIZE),
    _admin: str = Depends(current_admin),
) -> list[dict]:
    return get_recent(student_id, limit)


@router.get("/stream")
async def stream_events(
    student: str = Query(..., min_length=1),
    _admin: str = Depends(current_admin),
) -> StreamingResponse:
    q: asyncio.Queue = asyncio.Queue(maxsize=256)
    async with _lock:
        _subscribers[student].append(q)

    async def gen():
        try:
            yield b": vitos events stream\n\n"
            for ev in get_recent(student, 50):
                yield b"data: " + json.dumps(ev).encode() + b"\n\n"
            while True:
                ev = await q.get()
                yield b"data: " + json.dumps(ev).encode() + b"\n\n"
        finally:
            async with _lock:
                if q in _subscribers.get(student, []):
                    _subscribers[student].remove(q)

    return StreamingResponse(gen(), media_type="text/event-stream")
