"""Per-session ttyd reverse-proxy.

Lazy-spawns one `ttyd` subprocess per student session bound to a random
loopback port, then bridges the dashboard's WebSocket client to ttyd's
WebSocket. Read-only by default — admin must pass ?write=1 to enable
keystroke pass-through.

The ttyd commandline attaches to a tmux session named `student-<sid>`.
If no such tmux session exists, ttyd starts a fresh shell — useful for
the smoke test, harmless in production.
"""
from __future__ import annotations

import asyncio
import logging
import os
import re
import shutil
import socket
from dataclasses import dataclass

from fastapi import APIRouter, Depends, HTTPException, Query, WebSocket, WebSocketDisconnect

from .auth import current_admin, lookup_session
from .audit import write as audit_write

router = APIRouter()
log = logging.getLogger("vitos.ttyd")

_SESSION_RE = re.compile(r"^[A-Za-z0-9._-]+$")


@dataclass
class _TtydInstance:
    port: int
    proc: asyncio.subprocess.Process


_instances: dict[str, _TtydInstance] = {}
_lock = asyncio.Lock()


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


async def _ensure_ttyd(session_id: str, writable: bool) -> _TtydInstance:
    async with _lock:
        inst = _instances.get(session_id)
        if inst and inst.proc.returncode is None:
            return inst
        ttyd = shutil.which("ttyd")
        if not ttyd:
            raise HTTPException(status_code=500, detail="ttyd binary not installed")
        port = _free_port()
        cmd = [ttyd, "-p", str(port), "-i", "127.0.0.1"]
        if not writable:
            cmd.append("-R")  # read-only
        cmd += ["bash", "-c", f"tmux attach -t student-{session_id} 2>/dev/null || bash"]
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
        )
        for _ in range(20):
            await asyncio.sleep(0.05)
            try:
                with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                    s.connect(("127.0.0.1", port))
                break
            except OSError:
                continue
        inst = _TtydInstance(port=port, proc=proc)
        _instances[session_id] = inst
        return inst


@router.websocket("/{session_id}/ws")
async def proxy_ws(
    websocket: WebSocket,
    session_id: str,
    write: int = Query(0),
):
    sid_cookie = websocket.cookies.get("vitos_sid", "")
    admin = lookup_session(sid_cookie)
    if not admin:
        await websocket.close(code=4401)
        return
    if not _SESSION_RE.match(session_id):
        await websocket.close(code=4400)
        return

    writable = bool(write)
    audit_write(admin, "term.attach", session_id, "rw" if writable else "ro")

    try:
        inst = await _ensure_ttyd(session_id, writable)
    except HTTPException as e:
        await websocket.close(code=4500, reason=e.detail)
        return

    await websocket.accept(subprotocol="tty")

    try:
        import websockets
    except ImportError:
        await websocket.close(code=4500, reason="websockets package missing")
        return

    upstream_url = f"ws://127.0.0.1:{inst.port}/ws"
    try:
        async with websockets.connect(upstream_url, subprotocols=["tty"]) as upstream:
            async def client_to_upstream():
                try:
                    while True:
                        msg = await websocket.receive()
                        if msg["type"] == "websocket.disconnect":
                            return
                        if msg.get("bytes") is not None:
                            await upstream.send(msg["bytes"])
                        elif msg.get("text") is not None:
                            await upstream.send(msg["text"])
                except WebSocketDisconnect:
                    return

            async def upstream_to_client():
                try:
                    async for frame in upstream:
                        if isinstance(frame, bytes):
                            await websocket.send_bytes(frame)
                        else:
                            await websocket.send_text(frame)
                except Exception:  # noqa: BLE001
                    return

            await asyncio.gather(client_to_upstream(), upstream_to_client())
    except (OSError, ConnectionError) as e:
        log.warning("ttyd proxy error for %s: %s", session_id, e)
    finally:
        try:
            await websocket.close()
        except Exception:  # noqa: BLE001
            pass


@router.delete("/{session_id}")
async def kill_ttyd(session_id: str, _admin: str = Depends(current_admin)) -> dict:
    async with _lock:
        inst = _instances.pop(session_id, None)
    if inst and inst.proc.returncode is None:
        try:
            inst.proc.terminate()
            await asyncio.wait_for(inst.proc.wait(), timeout=2)
        except (asyncio.TimeoutError, ProcessLookupError):
            try:
                os.kill(inst.proc.pid, 9)
            except ProcessLookupError:
                pass
    return {"ok": True}
