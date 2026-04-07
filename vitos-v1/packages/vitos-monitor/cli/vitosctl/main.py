import json
import os
import pathlib
import signal
import subprocess
from datetime import datetime, timedelta, timezone

import click
from rich.console import Console
from rich.table import Table

DEFAULT_ALERT_LOG = "/var/log/vitos/alerts.jsonl"
DEFAULT_EVENT_LOG = "/var/log/vitos/events.jsonl"

console = Console()


def _parse_since(s: str) -> datetime:
    now = datetime.now(timezone.utc)
    if s.endswith("h"):
        return now - timedelta(hours=int(s[:-1]))
    if s.endswith("m"):
        return now - timedelta(minutes=int(s[:-1]))
    if s.endswith("d"):
        return now - timedelta(days=int(s[:-1]))
    return datetime.fromisoformat(s)


@click.group()
def cli():
    """VITOS admin command-line interface."""


@cli.command()
def status():
    """Show VITOS service status."""
    units = ["vitos-busd", "vitos-bpf-exec", "vitos-bpf-net",
             "vitos-shell-tap", "vitos-udev-tap", "vitos-fanotify-tap",
             "ollama", "vitos-ai"]
    table = Table(title="VITOS services")
    table.add_column("Service")
    table.add_column("State")
    for u in units:
        try:
            out = subprocess.check_output(["systemctl", "is-active", u], text=True).strip()
        except subprocess.CalledProcessError as e:
            out = (e.output or "unknown").strip()
        table.add_row(u, out)
    console.print(table)


@cli.command()
@click.option("--log", "log_path", default=DEFAULT_ALERT_LOG)
@click.option("--since", default="24h")
@click.option("--min-score", type=int, default=0)
def alerts(log_path, since, min_score):
    """Tail and filter the VITOS alert log."""
    p = pathlib.Path(log_path)
    if not p.exists():
        click.echo(f"No alert log at {log_path}")
        return
    cutoff = _parse_since(since)
    table = Table(title=f"Alerts since {since} (min score {min_score})")
    for col in ("Time", "Student", "Session", "Cat", "Score", "Reason"):
        table.add_column(col)
    for line in p.read_text().splitlines():
        try:
            a = json.loads(line)
        except json.JSONDecodeError:
            continue
        try:
            ts = datetime.fromisoformat(a["ts"].replace("Z", "+00:00"))
        except (KeyError, ValueError):
            continue
        if ts < cutoff:
            continue
        if int(a.get("score", 0)) < min_score:
            continue
        table.add_row(a["ts"], a.get("student_id", ""), a.get("session_id", ""),
                      a.get("category", ""), str(a.get("score", "")),
                      (a.get("ai_reason", "") or "")[:60])
    console.print(table)


@cli.group()
def session():
    """Per-session controls."""


@session.command("list")
def session_list():
    """List active student sessions."""
    d = pathlib.Path("/run/vitos/sessions")
    if not d.exists():
        click.echo("(no active sessions)")
        return
    for f in sorted(d.iterdir()):
        click.echo(f.name)


@session.command("freeze")
@click.argument("session_id")
def session_freeze(session_id):
    """Send SIGSTOP to a session's namespace PID 1 (resumable)."""
    pid_f = pathlib.Path(f"/run/vitos/sessions/{session_id}/pid")
    if not pid_f.exists():
        click.echo("session not found")
        return
    pid = int(pid_f.read_text().strip())
    os.kill(pid, signal.SIGSTOP)
    click.echo(f"froze {session_id} (pid {pid})")


@session.command("isolate")
@click.argument("session_id")
@click.option("--revert", is_flag=True)
def session_isolate(session_id, revert):
    """Drop or restore a session's network namespace veth."""
    veth = f"vitos-{session_id[:8]}"
    if revert:
        subprocess.run(["ip", "link", "set", veth, "up"], check=False)
        click.echo(f"restored {veth}")
    else:
        subprocess.run(["ip", "link", "set", veth, "down"], check=False)
        click.echo(f"isolated {veth}")


@cli.command()
@click.argument("manifest", type=click.Path(exists=True))
def scope(manifest):
    """Activate a lab-exercise scope manifest."""
    target = pathlib.Path("/etc/vitos/lab-scopes/active.yaml")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(pathlib.Path(manifest).read_text())
    subprocess.run(["systemctl", "restart", "vitos-ai"], check=False)
    click.echo(f"scope activated from {manifest}")


@cli.command()
@click.argument("student_id")
@click.option("--log", "log_path", default=DEFAULT_ALERT_LOG)
def report(student_id, log_path):
    """Render a Markdown incident summary for a student."""
    p = pathlib.Path(log_path)
    rows = []
    if p.exists():
        for line in p.read_text().splitlines():
            try:
                a = json.loads(line)
            except json.JSONDecodeError:
                continue
            if a.get("student_id") == student_id:
                rows.append(a)
    click.echo(f"# VITOS report — {student_id}\n")
    click.echo(f"Total alerts: {len(rows)}\n")
    for a in rows[-20:]:
        click.echo(f"- **{a.get('ts')}** — {a.get('category')} "
                   f"(score {a.get('score')}): {a.get('ai_reason','')}")


if __name__ == "__main__":
    cli()
