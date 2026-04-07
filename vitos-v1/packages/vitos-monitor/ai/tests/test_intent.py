from vitos_ai.intent import IntentClassifier, IntentLabel


def test_offline_fallback_returns_unknown():
    ic = IntentClassifier(endpoint="http://127.0.0.1:1", model="vitos-intent")
    label, conf, reason = ic.classify("nmap -sS 10.10.1.0/24")
    assert label == IntentLabel.UNKNOWN
    assert conf == 0.0
    assert "unreachable" in reason.lower() or "offline" in reason.lower()
