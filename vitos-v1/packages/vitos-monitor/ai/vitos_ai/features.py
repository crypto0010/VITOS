from collections import defaultdict, deque
from datetime import datetime, timedelta
from typing import Any


def _parse_ts(s: str) -> datetime:
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


class FeatureExtractor:
    """Rolling per-(student, session) feature window."""

    FIELDS = (
        "exec_count", "sudo_tries", "bytes_out", "bytes_in",
        "unique_dst_ips", "unique_dst_ports",
        "sensitive_reads", "usb_inserts",
    )

    def __init__(self, window_seconds: int = 60):
        self.window = timedelta(seconds=window_seconds)
        self._events: dict[tuple[str, str], deque] = defaultdict(deque)

    def ingest(self, ev: dict[str, Any]) -> None:
        sid = ev.get("student_id")
        sess = ev.get("session_id")
        if not sid or not sess:
            return
        try:
            ts = _parse_ts(ev["ts"])
        except (KeyError, ValueError):
            return
        q = self._events[(sid, sess)]
        q.append((ts, ev))
        cutoff = ts - self.window
        while q and q[0][0] < cutoff:
            q.popleft()

    def snapshot(self, student_id: str, session_id: str) -> dict[str, float]:
        q = self._events.get((student_id, session_id), deque())
        f = {k: 0 for k in self.FIELDS}
        dst_ips: set[str] = set()
        dst_ports: set[int] = set()
        for _, ev in q:
            t = ev.get("type")
            if t == "exec":
                f["exec_count"] += 1
                if ev.get("comm") == "sudo":
                    f["sudo_tries"] += 1
            elif t == "net_flow":
                f["bytes_out"] += int(ev.get("bytes", 0))
                if ev.get("daddr"):
                    dst_ips.add(ev["daddr"])
                if ev.get("dport") is not None:
                    dst_ports.add(int(ev["dport"]))
            elif t == "file_access":
                p = ev.get("path", "")
                if p in ("/etc/passwd", "/etc/shadow") or p.startswith("/root"):
                    f["sensitive_reads"] += 1
            elif t == "usb_event" and ev.get("action") == "add":
                f["usb_inserts"] += 1
        f["unique_dst_ips"] = len(dst_ips)
        f["unique_dst_ports"] = len(dst_ports)
        return f
