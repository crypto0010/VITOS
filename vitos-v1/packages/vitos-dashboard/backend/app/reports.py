"""Incident reports — Markdown + weasyprint PDF. Stub for SP5 Task 7."""
import subprocess
from fastapi import APIRouter, HTTPException
from fastapi.responses import PlainTextResponse, Response

router = APIRouter()


def _vitosctl_report(student_id: str) -> str:
    try:
        return subprocess.check_output(["vitosctl", "report", student_id], text=True)
    except (FileNotFoundError, subprocess.CalledProcessError) as e:
        raise HTTPException(status_code=500, detail=f"vitosctl error: {e}")


@router.get("/{student_id}/report")
def report_md(student_id: str) -> PlainTextResponse:
    return PlainTextResponse(_vitosctl_report(student_id), media_type="text/markdown")


@router.get("/{student_id}/report.pdf")
def report_pdf(student_id: str) -> Response:
    md = _vitosctl_report(student_id)
    try:
        from weasyprint import HTML  # noqa: WPS433
        html = f"<html><body><pre>{md}</pre></body></html>"
        pdf_bytes = HTML(string=html).write_pdf()
        return Response(content=pdf_bytes, media_type="application/pdf")
    except ImportError:
        raise HTTPException(status_code=500, detail="weasyprint missing")
