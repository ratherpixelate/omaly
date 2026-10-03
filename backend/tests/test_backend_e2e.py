"""End-to-end integration tests verifying all 5 backend endpoints against real data."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from fastapi.testclient import TestClient
from main import app
from api import wrapped

client = TestClient(app)


def test_health_endpoint():
    res = client.get("/health")
    assert res.status_code == 200
    assert res.json() == {"status": "ok"}


def test_search_endpoint():
    res = client.get("/search?q=friends&top_k=5")
    assert res.status_code == 200
    data = res.json()
    assert data["query"] == "friends"
    assert isinstance(data["results"], list)
    assert len(data["results"]) > 0

    first = data["results"][0]
    assert "id" in first
    assert "thumbnail_url" in first
    assert "taken_at" in first
    assert first["taken_at"] is not None
    assert "score" in first
    assert isinstance(first["score"], float)
    if first["location"] is not None:
        assert "lat" in first["location"]
        assert "lon" in first["location"]


def test_best_shot_endpoint():
    res = client.get("/best-shot?group_id=b_9d9a2f55")
    assert res.status_code == 200
    data = res.json()
    assert data["group_id"] == "b_9d9a2f55"
    assert "best_photo_id" in data
    assert isinstance(data["candidates"], list)
    assert data["best_photo_id"] in data["candidates"]
    assert "scores" in data


def test_wrapped_endpoint_real_data():
    res = client.get("/wrapped")
    assert res.status_code == 200
    data = res.json()
    assert "generated_at" in data
    assert "top_people" in data
    assert isinstance(data["top_people"], list)
    for p in data["top_people"]:
        assert "cluster_id" in p
        assert "label" in p and isinstance(p["label"], str) and len(p["label"]) > 0
        assert "photo_count" in p and p["photo_count"] >= 2

    assert "top_locations" in data
    assert isinstance(data["top_locations"], list)
    for loc in data["top_locations"]:
        assert "name" in loc and isinstance(loc["name"], str)
        assert "lat" in loc
        assert "lon" in loc
        assert "photo_count" in loc

    assert "pets_detected" in data
    assert isinstance(data["pets_detected"], bool)

    assert "best_shots" in data
    assert isinstance(data["best_shots"], list)
    assert len(data["best_shots"]) <= 5
    for s in data["best_shots"]:
        assert isinstance(s, str)

    assert "narrative" in data
    assert isinstance(data["narrative"], str)
    assert len(data["narrative"]) > 10

    # New Wrapped schema assertions:
    assert "year" in data and isinstance(data["year"], int)
    assert "photos_in_year" in data and isinstance(data["photos_in_year"], list)
    assert "photos_taken_in_year" in data and isinstance(data["photos_taken_in_year"], list)
    assert "statistics" in data and isinstance(data["statistics"], dict)

    stats = data["statistics"]
    assert "total_photos" in stats and isinstance(stats["total_photos"], int)
    assert "most_photos_taken_in_a_day" in stats
    if stats["most_photos_taken_in_a_day"]:
        assert "date" in stats["most_photos_taken_in_a_day"]
        assert "photo_count" in stats["most_photos_taken_in_a_day"]
    assert "most_visited_location" in stats
    assert "most_photos_with_a_person" in stats
    if stats["most_photos_with_a_person"]:
        assert "cluster_id" in stats["most_photos_with_a_person"]
        assert "photo_count" in stats["most_photos_with_a_person"]
    assert "busiest_month" in stats
    if stats["busiest_month"]:
        assert "month" in stats["busiest_month"]
        assert "photo_count" in stats["busiest_month"]


def test_wrapped_fallback_when_ollama_unavailable(monkeypatch):
    """Verify that if Ollama is unreachable, /wrapped still succeeds with a clean narrative."""
    # Force Ollama URL to invalid port
    monkeypatch.setattr(wrapped, "OLLAMA_URL", "http://127.0.0.1:99999/api/generate")

    res = client.get("/wrapped")
    assert res.status_code == 200
    data = res.json()
    assert "narrative" in data
    assert isinstance(data["narrative"], str)
    assert "You captured" in data["narrative"]


def test_thumbnails_endpoint():
    # Pick a real photo id from search
    res = client.get("/search?q=photo&top_k=1")
    assert res.status_code == 200
    photo_id = res.json()["results"][0]["id"]

    thumb_res = client.get(f"/thumbnails/{photo_id}.jpg")
    assert thumb_res.status_code == 200
    assert thumb_res.headers.get("content-type") == "image/jpeg"
    assert len(thumb_res.content) > 0


if __name__ == "__main__":
    print("Testing /health...")
    test_health_endpoint()
    print("Testing /search...")
    test_search_endpoint()
    print("Testing /best-shot...")
    test_best_shot_endpoint()
    print("Testing /wrapped (real data)...")
    test_wrapped_endpoint_real_data()

    class SimplePatch:
        def __init__(self):
            self.undo = []
        def setattr(self, target, name, value):
            self.undo.append((target, name, getattr(target, name)))
            setattr(target, name, value)
        def restore(self):
            for target, name, orig in reversed(self.undo):
                setattr(target, name, orig)
            self.undo.clear()

    patch = SimplePatch()
    try:
        print("Testing /wrapped (fallback when Ollama unreachable)...")
        test_wrapped_fallback_when_ollama_unavailable(patch)
    finally:
        patch.restore()

    print("Testing /thumbnails...")
    test_thumbnails_endpoint()

    print("\nALL BACKEND END-TO-END TESTS PASSED! \u2714")
