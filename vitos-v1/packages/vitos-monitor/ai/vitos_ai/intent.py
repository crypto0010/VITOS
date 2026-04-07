import json
from enum import Enum

import httpx


class IntentLabel(str, Enum):
    BENIGN = "BENIGN"
    RECON = "RECON"
    EXPLOIT = "EXPLOIT"
    EXFIL = "EXFIL"
    LATERAL = "LATERAL"
    UNKNOWN = "UNKNOWN"


LABEL_RISK = {
    IntentLabel.BENIGN: 0.0,
    IntentLabel.RECON: 0.3,
    IntentLabel.EXPLOIT: 0.9,
    IntentLabel.EXFIL: 0.95,
    IntentLabel.LATERAL: 0.85,
    IntentLabel.UNKNOWN: 0.0,
}

PROMPT = """You classify a single shell command from a university cybersecurity \
lab session. Reply with strictly one JSON object:
{"label":"BENIGN|RECON|EXPLOIT|EXFIL|LATERAL","confidence":0.0-1.0,"reason":"<one sentence>"}
Command: """


class IntentClassifier:
    def __init__(self, endpoint: str = "http://127.0.0.1:11434",
                 model: str = "vitos-intent", timeout: float = 4.0):
        self.endpoint = endpoint.rstrip("/")
        self.model = model
        self.timeout = timeout

    def classify(self, command: str) -> tuple[IntentLabel, float, str]:
        try:
            r = httpx.post(
                f"{self.endpoint}/api/generate",
                json={"model": self.model, "prompt": PROMPT + command,
                      "stream": False, "format": "json"},
                timeout=self.timeout,
            )
            r.raise_for_status()
            data = r.json()
            obj = json.loads(data.get("response", "{}"))
            label = IntentLabel(obj.get("label", "UNKNOWN"))
            conf = float(obj.get("confidence", 0.0))
            reason = str(obj.get("reason", ""))
            return label, conf, reason
        except (httpx.HTTPError, json.JSONDecodeError, ValueError, KeyError) as e:
            return IntentLabel.UNKNOWN, 0.0, f"Ollama unreachable/offline: {e}"
