from vitos_ai.features import FeatureExtractor


def test_extracts_window():
    fx = FeatureExtractor(window_seconds=60)
    fx.ingest({"ts": "2026-04-07T00:00:00Z", "type": "exec",
               "student_id": "s1", "session_id": "x", "comm": "nmap"})
    fx.ingest({"ts": "2026-04-07T00:00:05Z", "type": "net_flow",
               "student_id": "s1", "session_id": "x",
               "daddr": "10.10.1.5", "dport": 22, "bytes": 4096})
    fx.ingest({"ts": "2026-04-07T00:00:06Z", "type": "net_flow",
               "student_id": "s1", "session_id": "x",
               "daddr": "10.10.1.6", "dport": 22, "bytes": 4096})
    feats = fx.snapshot("s1", "x")
    assert feats["exec_count"] == 1
    assert feats["bytes_out"] == 8192
    assert feats["unique_dst_ips"] == 2
    assert feats["unique_dst_ports"] == 1


def test_empty_session_returns_zeros():
    fx = FeatureExtractor(window_seconds=60)
    feats = fx.snapshot("nobody", "nosess")
    assert feats["exec_count"] == 0
    assert feats["bytes_out"] == 0
