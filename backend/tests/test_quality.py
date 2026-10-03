"""Unit tests for the Eye-Aware & Clarity-Based Best-Shot Picker."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import sqlite3
import numpy as np
from fastapi.testclient import TestClient

from ingestion import quality
from main import app

client = TestClient(app)


def test_ear_calculation():
    # Synthetic eye landmarks (6 points: p0..p5)
    # p0: (0, 0), p3: (10, 0) -> width = 10
    # p1: (3, 3), p5: (3, -3) -> v1 = 6
    # p2: (7, 3), p4: (7, -3) -> v2 = 6
    # EAR = (6 + 6) / (2 * 10) = 12 / 20 = 0.60
    open_eye = np.array([
        [0.0, 0.0],
        [3.0, 3.0],
        [7.0, 3.0],
        [10.0, 0.0],
        [7.0, -3.0],
        [3.0, -3.0],
    ])
    ear_val = quality._ear(open_eye)
    assert ear_val is not None
    assert round(ear_val, 2) == 0.60

    # Closed eye: vertical distance is tiny
    closed_eye = np.array([
        [0.0, 0.0],
        [3.0, 0.5],
        [7.0, 0.5],
        [10.0, 0.0],
        [7.0, -0.5],
        [3.0, -0.5],
    ])
    ear_closed = quality._ear(closed_eye)
    assert ear_closed is not None
    assert round(ear_closed, 2) == 0.10
    assert ear_closed <= quality.EAR_HARD


def test_yaw_gating():
    # 68 landmark array
    lm = np.zeros((68, 2))
    # Eye midpoints
    lm[36:42] = [40.0, 50.0]  # left eye
    lm[42:48] = [60.0, 50.0]  # right eye
    # Midpoint x = 50.0, interocular = 20.0

    # Frontal nose: nose_x = 51.0 -> |51-50| / 20 = 0.05 <= 0.40 -> True
    lm[30] = [51.0, 70.0]
    assert quality._yaw_ok(lm) is True

    # Profile nose: nose_x = 75.0 -> |75-50| / 20 = 1.25 > 0.40 -> False
    lm[30] = [75.0, 70.0]
    assert quality._yaw_ok(lm) is False


def test_laplacian_sharpness():
    # Blurry constant/smooth array
    smooth = np.ones((50, 50), dtype=np.float64) * 128.0
    var_smooth = quality._lap_var(smooth)
    assert var_smooth == 0.0

    # High frequency / textured / sharp array
    sharp = np.zeros((50, 50), dtype=np.float64)
    sharp[::2, ::2] = 255.0
    var_sharp = quality._lap_var(sharp)
    assert var_sharp > 1000.0


def test_rank_group_tier_first(monkeypatch):
    """Test that a photo with 0 closed eyes outranks a photo with closed eyes,
    even if the closed-eye photo has higher sharpness."""
    con = sqlite3.connect(":memory:")

    # Mock get_metrics to return controlled synthetic values
    # Photo A: 0 closed eyes, moderate sharpness
    # Photo B: 1 closed eye, maximum sharpness
    fake_metrics = {
        "p_open": {
            "size": [1000, 1000],
            "global_sharp": 100.0,
            "faces": [{
                "bbox": [100, 100, 200, 200],
                "det": 0.9,
                "small": False,
                "ears": [0.35, 0.35],
                "yaw_ok": True,
                "face_sharp": 150.0,
            }],
        },
        "p_closed": {
            "size": [1000, 1000],
            "global_sharp": 500.0,
            "faces": [{
                "bbox": [100, 100, 200, 200],
                "det": 0.9,
                "small": False,
                "ears": [0.10, 0.10],  # Closed eye!
                "yaw_ok": True,
                "face_sharp": 600.0,
            }],
        },
    }

    monkeypatch.setattr(quality, "get_metrics", lambda c, pid, fp: (fake_metrics[pid], True))

    rows = [
        ("p_closed", "/fake/b.jpg", "2026-01-01T12:00:01", '["p1"]'),
        ("p_open", "/fake/a.jpg", "2026-01-01T12:00:00", '["p1"]'),
    ]

    ranked = quality.rank_group(con, rows)
    assert len(ranked) == 2
    # Photo with open eyes must win (Rank 1)
    assert ranked[0]["photo_id"] == "p_open"
    assert ranked[0]["blink_tier"] == 0
    assert ranked[0]["n_closed"] == 0

    # Photo with closed eye is Tier 1
    assert ranked[1]["photo_id"] == "p_closed"
    assert ranked[1]["blink_tier"] == 1
    assert ranked[1]["n_closed"] == 1


def test_rank_group_landscape_burst(monkeypatch):
    """Test that a burst with no faces ranks purely by sharpness."""
    con = sqlite3.connect(":memory:")

    fake_metrics = {
        "scenery_soft": {
            "size": [1000, 1000],
            "global_sharp": 50.0,
            "faces": [],
        },
        "scenery_sharp": {
            "size": [1000, 1000],
            "global_sharp": 350.0,
            "faces": [],
        },
    }

    monkeypatch.setattr(quality, "get_metrics", lambda c, pid, fp: (fake_metrics[pid], True))

    rows = [
        ("scenery_soft", "/fake/soft.jpg", "2026-01-01T12:00:00", None),
        ("scenery_sharp", "/fake/sharp.jpg", "2026-01-01T12:00:01", None),
    ]

    ranked = quality.rank_group(con, rows)
    assert len(ranked) == 2
    assert ranked[0]["photo_id"] == "scenery_sharp"
    assert ranked[1]["photo_id"] == "scenery_soft"
    assert ranked[0]["blink_tier"] == 0
    assert ranked[0]["n_faces"] == 0


def test_best_shot_api():
    # Real demo burst b_9d9a2f55
    res = client.get("/best-shot?group_id=b_9d9a2f55")
    assert res.status_code == 200
    data = res.json()
    assert data["group_id"] == "b_9d9a2f55"
    assert "best_photo_id" in data
    assert isinstance(data["candidates"], list)
    assert len(data["candidates"]) >= 1
    assert "scores" in data
    assert len(data["scores"]) == 3

    # Test top_k override
    res_k2 = client.get("/best-shot?group_id=b_9d9a2f55&top_k=2")
    assert res_k2.status_code == 200
    assert len(res_k2.json()["candidates"]) == 2

    # Test 404 for nonexistent group
    res_404 = client.get("/best-shot?group_id=nonexistent_group")
    assert res_404.status_code == 404


def test_list_bursts_api():
    res = client.get("/bursts")
    assert res.status_code == 200
    data = res.json()
    assert "bursts" in data
    assert isinstance(data["bursts"], list)
    assert len(data["bursts"]) >= 1
    burst = data["bursts"][0]
    assert burst["group_id"] == "b_9d9a2f55"
    assert burst["photo_count"] == 3
    assert "best_photo_id" in burst
    assert "photos" in burst
    assert len(burst["photos"]) == 3
    best_photos = [p for p in burst["photos"] if p["is_best"]]
    assert len(best_photos) == 1
    assert best_photos[0]["id"] == burst["best_photo_id"]
    assert "thumbnail_url" in best_photos[0]
    assert "score" in best_photos[0]


if __name__ == "__main__":
    print("Running test_ear_calculation...")
    test_ear_calculation()
    print("Running test_yaw_gating...")
    test_yaw_gating()
    print("Running test_laplacian_sharpness...")
    test_laplacian_sharpness()

    class SimpleMonkeyPatch:
        def __init__(self):
            self.undo = []
        def setattr(self, target, name, value):
            self.undo.append((target, name, getattr(target, name)))
            setattr(target, name, value)
        def restore(self):
            for target, name, orig in reversed(self.undo):
                setattr(target, name, orig)
            self.undo.clear()

    patch = SimpleMonkeyPatch()
    try:
        print("Running test_rank_group_tier_first...")
        test_rank_group_tier_first(patch)
    finally:
        patch.restore()

    try:
        print("Running test_rank_group_landscape_burst...")
        test_rank_group_landscape_burst(patch)
    finally:
        patch.restore()

    print("Running test_best_shot_api...")
    test_best_shot_api()
    print("Running test_list_bursts_api...")
    test_list_bursts_api()
    print("\nALL TESTS PASSED! \u2714")
