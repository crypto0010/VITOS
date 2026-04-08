"""Incident reports — Markdown via vitosctl, PDF via weasyprint + Jinja2 template."""
from __future__ import annotations

import json
import subprocess
import time
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import PlainTextResponse, Response

from .auth import current_admin
from .audit import write as audit_write

ALERT_LOG = Path("/var/log/vitos/alerts.jsonl")
TEMPLATE_DIR = Path("/usr/lib/vitos/dashboard/templates")

router = APIRouter()


def _vitosctl_report(student_id: str) -> str:
    try:
        return subprocess.check_output(["vitosctl", "report", student_id], text=True)
    except FileNotFoundError as e:
        raise HTTPException(status_code=500, detail=f"vitosctl missing: {e}")
    except subprocess.CalledProcessError as e:
        raise HTTPException(status_code=500, detail=f"vitosctl error: {e}")


def _alerts_for(student_id: str) -> list[dict]:
    if not ALERT_LOG.exists():
        return []
    out = []
    for line in ALERT_LOG.read_text().splitlines():
        try:
            a = json.loads(line)
        except json.JSONDecodeError:
            continue
        if a.get("student_id") == student_id:
            out.append(a)
    return out


@router.get("/{student_id}/report")
def report_md(student_id: str, admin: str = Depends(current_admin)) -> PlainTextResponse:
    audit_write(admin, "report.md", student_id, "ok")
    return PlainTextResponse(_vitosctl_report(student_id), media_type="text/markdown")


@router.get("/{student_id}/report.pdf")
def report_pdf(student_id: str, admin: str = Depends(current_admin)) -> Response:
    alerts = _alerts_for(student_id)
    audit_write(admin, "report.pdf", student_id, "ok")
    try:
        from weasyprint import HTML  # noqa: WPS433
        from jinja2 import Environment, FileSystemLoader, select_autoescape
    except ImportError as e:
        raise HTTPException(status_code=500, detail=f"missing dep: {e}")
    env = Environment(
        loader=FileSystemLoader(str(TEMPLATE_DIR)),
        autoescape=select_autoescape(["html", "xml"]),
    )
    tpl = env.get_template("incident-report.html.j2")
    html = tpl.render(
        student_id=student_id,
        alerts=alerts,
        ts=time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime()),
    )
    pdf_bytes = HTML(string=html).write_pdf()
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename=vitos-{student_id}.pdf"},
    )
