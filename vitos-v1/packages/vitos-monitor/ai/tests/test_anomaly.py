import numpy as np

from vitos_ai.anomaly import AnomalyModel
from vitos_ai.features import FeatureExtractor


def test_returns_zero_during_baseline():
    m = AnomalyModel(min_baseline_sessions=3)
    feats = {k: 0 for k in FeatureExtractor.FIELDS}
    feats["exec_count"] = 1
    score = m.score("student-A", feats, is_baseline=True)
    assert score == 0.0


def test_flags_outlier_after_baseline():
    rng = np.random.default_rng(42)
    m = AnomalyModel(min_baseline_sessions=3)
    for _sess in range(3):
        for _ in range(50):
            f = {k: 0 for k in FeatureExtractor.FIELDS}
            f["exec_count"] = int(rng.integers(0, 5))
            f["bytes_out"] = int(rng.integers(0, 1000))
            m.score("student-A", f, is_baseline=True)
        m.commit_baseline_session("student-A")
    outlier = {k: 0 for k in FeatureExtractor.FIELDS}
    outlier["exec_count"] = 500
    outlier["bytes_out"] = 10_000_000
    outlier["unique_dst_ips"] = 250
    score = m.score("student-A", outlier, is_baseline=False)
    assert score > 0.5
