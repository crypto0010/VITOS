import asyncio
import json
import os
import pathlib
import socket
import time
from typing import Any

import click
import yaml

from .features import FeatureExtractor
from .anomaly import AnomalyModel
from .intent import IntentClassifier, IntentLabel
from .scorer import RiskScorer, AlertCategory

DEFAULT_BUS = "/run/vitos/bus.sock.sub"
DEFAULT_ALERT_LOG = "/var/log/vitos/alerts.jsonl"


def load_scope(path: str) -> dict[str, Any]:
    p = pathlib.Path(path)
    if not p.exists():
        return {"allowed_targets": [], "allowed_ports": [], "allowed_tools": []}
    return yaml.safe_load(p.read_text())


def is_scope_breach(ev: dict, scope: dict) -> bool:
    if ev.get("type") == "tool_exec":
        tool = ev.get("tool")
        if scope["allowed_tools"] and tool not in scope["allowed_tools"]:
            return True
    if ev.get("type") == "net_flow":
        port = ev.get("dport")
        if port is not None and scope["allowed_ports"] and port not in scope["allowed_ports"]:
            return True
    return False


def isolate(student_id: str, session_id: str) -> None:
    """Best-effort namespace network drop via vitosctl."""
    try:
        os.system(f"vitosctl session isolate {session_id} >/dev/null 2>&1")
    except Exception:
        pass


async def run(bus_path: str, alert_log: str, scope_path: str,
              ollama_endpoint: str, ollama_model: str, lite: bool) -> None:
    fx = FeatureExtractor(window_seconds=60)
    am = AnomalyModel(min_baseline_sessions=3)
    ic = IntentClassifier(endpoint=ollama_endpoint, model=ollama_model)
    sc = RiskScorer()
    scope = load_scope(scope_path)

    pathlib.Path(alert_log).parent.mkdir(parents=True, exist_ok=True)
    out = open(alert_log, "a", buffering=1)

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    while True:
        try:
            sock.connect(bus_path)
            break
        except OSError:
            await asyncio.sleep(1)
    sock.setblocking(False)
    loop = asyncio.get_running_loop()

    last_score: dict[tuple[str, str], float] = {}
    buf = b""
    while True:
        chunk = await loop.sock_recv(sock, 65536)
        if not chunk:
            break
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                continue
            sid = ev.get("student_id")
            sess = ev.get("session_id")
            if not sid or not sess:
                continue
            fx.ingest(ev)
            feats = fx.snapshot(sid, sess)

            anomaly = 0.0 if lite else am.score(sid, feats, is_baseline=False)

            label, conf, reason = (IntentLabel.UNKNOWN, 0.0, "")
            if not lite and ev.get("type") in ("shell_cmd", "tool_exec"):
                cmd = ev.get("cmd") or " ".join(ev.get("argv", []))
                if cmd:
                    label, conf, reason = ic.classify(cmd)

            breach = is_scope_breach(ev, scope)
            cat, score = sc.score(anomaly, label, conf, breach)

            key = (sid, sess)
            if score < 20 and last_score.get(key, 100) < 20:
                continue
            last_score[key] = score

            if cat != AlertCategory.NORMAL:
                alert = {
                    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    "student_id": sid, "session_id": sess,
                    "category": cat.value, "score": score,
                    "anomaly": round(anomaly, 3),
                    "intent_label": label.value,
                    "intent_confidence": round(conf, 3),
                    "scope_breach": breach,
                    "ai_reason": reason,
                    "trigger_event": ev,
                }
                out.write(json.dumps(alert) + "\n")
                if cat == AlertCategory.CRITICAL:
                    isolate(sid, sess)


@click.command()
@click.option("--bus", default=DEFAULT_BUS)
@click.option("--alerts", default=DEFAULT_ALERT_LOG)
@click.option("--scope", default="/etc/vitos/lab-scopes/active.yaml")
@click.option("--ollama-endpoint", default="http://127.0.0.1:11434")
@click.option("--ollama-model", default="vitos-intent")
@click.option("--lite", is_flag=True, help="Disable LLM intent classification")
def main(bus, alerts, scope, ollama_endpoint, ollama_model, lite):
    asyncio.run(run(bus, alerts, scope, ollama_endpoint, ollama_model, lite))


if __name__ == "__main__":
    main()
