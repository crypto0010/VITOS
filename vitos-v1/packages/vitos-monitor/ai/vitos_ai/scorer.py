from enum import Enum

from .intent import IntentLabel, LABEL_RISK


class AlertCategory(str, Enum):
    NORMAL = "Normal"
    SUSPICIOUS = "Suspicious"
    WARNING = "Warning"
    CRITICAL = "Critical"


class RiskScorer:
    """Composite 0–100 score and categorization.

    Hard rule baked in: CRITICAL requires all three of:
      - anomaly > 0.7
      - malicious intent (EXPLOIT, EXFIL, LATERAL) with conf >= 0.6
      - scope_breach = True
    The LLM alone can never push the category past WARNING.
    """

    MALICIOUS = {IntentLabel.EXPLOIT, IntentLabel.EXFIL, IntentLabel.LATERAL}

    def score(self, anomaly: float, intent_label: IntentLabel,
              intent_conf: float, scope_breach: bool) -> tuple[AlertCategory, int]:
        intent_risk = LABEL_RISK[intent_label] * intent_conf
        composite = 60 * anomaly + 30 * intent_risk + 10 * (1 if scope_breach else 0)
        composite = int(round(min(100, max(0, composite))))

        critical = (
            anomaly > 0.7
            and intent_label in self.MALICIOUS
            and intent_conf >= 0.6
            and scope_breach
        )
        if critical:
            return AlertCategory.CRITICAL, max(composite, 80)
        if composite >= 50:
            return AlertCategory.WARNING, composite
        if composite >= 20:
            return AlertCategory.SUSPICIOUS, composite
        return AlertCategory.NORMAL, composite
