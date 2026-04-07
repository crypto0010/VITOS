import json
import pathlib
import tempfile

from click.testing import CliRunner

from vitosctl.main import cli


def test_alerts_filters_by_min_score():
    with tempfile.TemporaryDirectory() as d:
        log = pathlib.Path(d) / "alerts.jsonl"
        log.write_text(
            json.dumps({"ts": "2026-04-07T00:00:00Z", "student_id": "a",
                        "category": "Suspicious", "score": 25}) + "\n" +
            json.dumps({"ts": "2026-04-07T00:01:00Z", "student_id": "b",
                        "category": "Critical", "score": 92}) + "\n"
        )
        runner = CliRunner()
        r = runner.invoke(cli, ["alerts", "--log", str(log),
                                "--since", "365d", "--min-score", "50"])
        assert r.exit_code == 0
        assert "Critical" in r.output
        assert "Suspicious" not in r.output
