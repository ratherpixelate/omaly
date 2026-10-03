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
    assert "filename" in first and isinstance(first["filename"], str)
    assert "url" in first and first["url"].startswith("/files/")
    assert "burst_group_id" in first
    assert "thumbnail_url" in first
    assert "taken_at" in first
    assert first["taken_at"] is not None
    assert "score" in first
    assert isinstance(first["score"], float)
    if first["location"] is not None:
        assert "lat" in first["location"]
        assert "lon" in first["location"]


def test_search_by_person_name_and_filename():
    # 1. Search for person name "Chris" (cluster p1) - should strictly return only Chris photos
    res_chris = client.get("/search?q=Chris")
    assert res_chris.status_code == 200
    chris_results = res_chris.json()["results"]
    assert len(chris_results) == 11
    assert all(r.get("matched_person") == "Chris" for r in chris_results)
    assert all(r["score"] == 1.0 for r in chris_results)

    # 2. Rename cluster p4 to "E2E Test Person" and search for it, restoring afterward
    from api.common import db
    orig_label = None
    with db() as con:
        r = con.execute("SELECT label FROM face_clusters WHERE cluster_id = 'p4'").fetchone()
        if r:
            orig_label = r["label"]

    try:
        client.post("/people/p4/rename", json={"name": "E2E Test Person"})
        res_rename = client.get("/search?q=E2E Test Person")
        assert res_rename.status_code == 200
        renamed_results = res_rename.json()["results"]
        assert len(renamed_results) > 0
        assert "E2E Test Person" in renamed_results[0]["matched_person"]
        assert renamed_results[0]["score"] == 1.0
    finally:
        with db() as con:
            con.execute("UPDATE face_clusters SET label = ? WHERE cluster_id = 'p4'", (orig_label,))
            con.commit()

    # 3. Search by filename "0951"
    res_file = client.get("/search?q=0951")
    assert res_file.status_code == 200
    file_results = res_file.json()["results"]
    assert any("0951" in r["filename"] for r in file_results)


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


def test_wrapped_narrative_fast():
    """Verify that /wrapped returns a clean, deterministic narrative instantly with no Ollama dependency."""
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


def test_person_thumbnail_endpoint():
    # p1 exists in people
    res = client.get("/people/p1/thumbnail.jpg")
    assert res.status_code == 200
    assert res.headers.get("content-type") == "image/jpeg"
    assert len(res.content) > 0


if __name__ == "__main__":
    print("Testing /health...")
    test_health_endpoint()
    print("Testing /search...")
    test_search_endpoint()
    print("Testing /search by person name and filename...")
    test_search_by_person_name_and_filename()
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

    print("Testing /wrapped (fast deterministic narrative)...")
    test_wrapped_narrative_fast()

    print("Testing /thumbnails...")
    test_thumbnails_endpoint()
    print("Testing /people/{cluster_id}/thumbnail.jpg...")
    test_person_thumbnail_endpoint()

    print("\nALL BACKEND END-TO-END TESTS PASSED! \u2714")
