from vitos_ai.scorer import RiskScorer, AlertCategory
from vitos_ai.intent import IntentLabel


def test_critical_requires_all_three_signals():
    s = RiskScorer()
    cat, score = s.score(anomaly=0.8, intent_label=IntentLabel.EXPLOIT,
                         intent_conf=0.9, scope_breach=True)
    assert cat == AlertCategory.CRITICAL
    assert score >= 80

    cat2, _ = s.score(anomaly=0.95, intent_label=IntentLabel.EXPLOIT,
                      intent_conf=0.95, scope_breach=False)
    assert cat2 != AlertCategory.CRITICAL

    cat3, _ = s.score(anomaly=0.0, intent_label=IntentLabel.EXFIL,
                      intent_conf=0.99, scope_breach=False)
    assert cat3 in (AlertCategory.NORMAL, AlertCategory.SUSPICIOUS, AlertCategory.WARNING)
    assert cat3 != AlertCategory.CRITICAL


def test_normal_when_all_clean():
    s = RiskScorer()
    cat, score = s.score(anomaly=0.05, intent_label=IntentLabel.BENIGN,
                         intent_conf=0.9, scope_breach=False)
    assert cat == AlertCategory.NORMAL
    assert score < 20
