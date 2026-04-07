from collections import defaultdict
import numpy as np
from sklearn.ensemble import IsolationForest

from .features import FeatureExtractor


class AnomalyModel:
    """Per-student Isolation Forest. Returns 0.0 until min_baseline_sessions
    sessions of normal data have been collected, then a 0.0–1.0 score where
    higher = more anomalous."""

    def __init__(self, min_baseline_sessions: int = 3, contamination: float = 0.05):
        self._min = min_baseline_sessions
        self._contam = contamination
        self._buffers: dict[str, list[list[float]]] = defaultdict(list)
        self._models: dict[str, IsolationForest] = {}
        self._sessions_committed: dict[str, int] = defaultdict(int)

    @staticmethod
    def _vec(feats: dict[str, float]) -> list[float]:
        return [float(feats[k]) for k in FeatureExtractor.FIELDS]

    def score(self, student_id: str, feats: dict[str, float], is_baseline: bool) -> float:
        v = self._vec(feats)
        if is_baseline:
            self._buffers[student_id].append(v)
            return 0.0
        model = self._models.get(student_id)
        if model is None:
            return 0.0
        raw = -model.score_samples(np.array([v]))[0]  # higher = more anomalous
        return float(min(1.0, max(0.0, (raw + 0.5) / 1.5)))

    def commit_baseline_session(self, student_id: str) -> None:
        self._sessions_committed[student_id] += 1
        if self._sessions_committed[student_id] >= self._min:
            X = np.array(self._buffers[student_id])
            if len(X) >= 10:
                m = IsolationForest(contamination=self._contam, random_state=0)
                m.fit(X)
                self._models[student_id] = m

    def is_trained(self, student_id: str) -> bool:
        return student_id in self._models
