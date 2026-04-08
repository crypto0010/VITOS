import json
import os
import pathlib
import signal
import subprocess
import time
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


@cli.group()
def ghost():
    """Ghost Mode (SP6 / vitos-ghost) — dual-admin gated."""


GHOST_PENDING = pathlib.Path("/var/lib/vitos/ghost/pending")
GHOST_ACTIVE  = pathlib.Path("/var/lib/vitos/ghost/active")


def _current_user() -> str:
    return os.environ.get("SUDO_USER") or os.environ.get("USER") or "unknown"


def _in_group(user: str, group: str) -> bool:
    try:
        import grp
        return user in grp.getgrnam(group).gr_mem
    except (KeyError, ImportError):
        return False


@ghost.command("enable")
@click.argument("user")
@click.option("--profile", default="default")
def ghost_enable(user, profile):
    """Request ghost mode for USER. Requires admin to be in vitos-admins."""
    requester = _current_user()
    if not _in_group(requester, "vitos-admins"):
        click.echo(f"refused: {requester} is not in vitos-admins", err=True)
        raise SystemExit(13)
    GHOST_PENDING.mkdir(parents=True, exist_ok=True)
    req_id = f"{user}.{profile}"
    req_file = GHOST_PENDING / f"{req_id}.req"
    payload = {
        "id": req_id,
        "user": user,
        "profile": profile,
        "requester": requester,
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    req_file.write_text(json.dumps(payload, indent=2))
    click.echo(f"pending: {req_id} (request id {req_file})")
    click.echo("waiting for a vitos-ghost-approvers member to run:")
    click.echo(f"  vitosctl ghost approve {req_id}")


@ghost.command("approve")
@click.argument("req_id")
def ghost_approve(req_id):
    """Approve a pending ghost-mode request. Requires vitos-ghost-approvers."""
    approver = _current_user()
    if not _in_group(approver, "vitos-ghost-approvers"):
        click.echo(f"refused: {approver} is not in vitos-ghost-approvers", err=True)
        raise SystemExit(13)
    req_file = GHOST_PENDING / f"{req_id}.req"
    if not req_file.exists():
        click.echo(f"no such pending request: {req_id}", err=True)
        raise SystemExit(2)
    req = json.loads(req_file.read_text())
    if req["requester"] == approver:
        click.echo(f"refused: {approver} cannot self-approve their own request", err=True)
        raise SystemExit(13)
    GHOST_ACTIVE.mkdir(parents=True, exist_ok=True)
    active_file = GHOST_ACTIVE / f"{req['user']}.{req['profile']}"
    req["approver"] = approver
    req["approved_ts"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    active_file.write_text(json.dumps(req, indent=2))
    req_file.unlink()
    click.echo(f"approved: {req_id} (token {active_file})")


@ghost.command("list")
def ghost_list():
    """List pending and active ghost-mode requests."""
    click.echo("# pending")
    if GHOST_PENDING.exists():
        for f in sorted(GHOST_PENDING.glob("*.req")):
            click.echo(f"  {f.stem}")
    click.echo("# active")
    if GHOST_ACTIVE.exists():
        for f in sorted(GHOST_ACTIVE.iterdir()):
            click.echo(f"  {f.name}")


@ghost.command("disable")
@click.argument("req_id")
def ghost_disable(req_id):
    """Revoke an active ghost-mode token."""
    if not _in_group(_current_user(), "vitos-admins"):
        raise SystemExit(13)
    f = GHOST_ACTIVE / req_id
    if f.exists():
        f.unlink()
        click.echo(f"revoked: {req_id}")
    else:
        click.echo(f"no such active token: {req_id}", err=True)
        raise SystemExit(2)


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
