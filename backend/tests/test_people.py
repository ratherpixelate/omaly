import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import unittest
from fastapi.testclient import TestClient

from main import app

client = TestClient(app)


class TestPeopleEndpoints(unittest.TestCase):
    def test_list_people(self):
        res = client.get("/people")
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertIn("people", data)
        people = data["people"]
        self.assertGreater(len(people), 0)
        p1 = people[0]
        self.assertIn("id", p1)
        self.assertIn("name", p1)
        self.assertIn("photo_count", p1)
        self.assertIn("cover_photo_id", p1)
        self.assertIn("thumbnail_url", p1)

    def test_get_person_photos(self):
        # p1 exists in demo db
        res = client.get("/people/p1/photos")
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data["cluster_id"], "p1")
        self.assertIn("photos", data)
        self.assertGreater(len(data["photos"]), 0)
        photo = data["photos"][0]
        self.assertIn("id", photo)
        self.assertIn("name", photo)
        self.assertIn("url", photo)
        self.assertIn("thumbnail_url", photo)

    def test_get_person_photos_not_found(self):
        res = client.get("/people/non_existent_cluster/photos")
        self.assertEqual(res.status_code, 404)

    def test_rename_person(self):
        # Save original label of p2
        from api.common import db
        orig_label = None
        with db() as con:
            r = con.execute("SELECT label FROM face_clusters WHERE cluster_id = 'p2'").fetchone()
            if r:
                orig_label = r["label"]

        try:
            # Rename p2
            res = client.post("/people/p2/rename", json={"name": "Test Name"})
            self.assertEqual(res.status_code, 200)
            data = res.json()
            self.assertEqual(data["id"], "p2")
            self.assertEqual(data["name"], "Test Name")
            self.assertIn("thumbnail_url", data)
            self.assertIsNotNone(data["thumbnail_url"])
            self.assertIn("cover_photo_id", data)
            self.assertIsNotNone(data["cover_photo_id"])

            # Verify reflected in list
            list_res = client.get("/people")
            self.assertEqual(list_res.status_code, 200)
            p2 = next(p for p in list_res.json()["people"] if p["id"] == "p2")
            self.assertEqual(p2["name"], "Test Name")
        finally:
            with db() as con:
                con.execute("UPDATE face_clusters SET label = ? WHERE cluster_id = 'p2'", (orig_label,))
                con.commit()

    def test_rename_person_empty_rejected(self):
        res = client.post("/people/p2/rename", json={"name": "   "})
        self.assertEqual(res.status_code, 400)

    def test_person_face_thumbnail(self):
        # /people/p1/thumbnail.jpg should return a valid JPEG face crop
        res = client.get("/people/p1/thumbnail.jpg")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.headers.get("content-type"), "image/jpeg")
        self.assertGreater(len(res.content), 0)

        # /people/p1/thumbnail route alias
        res_alias = client.get("/people/p1/thumbnail")
        self.assertEqual(res_alias.status_code, 200)
        self.assertEqual(res_alias.headers.get("content-type"), "image/jpeg")
        self.assertGreater(len(res_alias.content), 0)

    def test_person_face_thumbnail_not_found(self):
        res = client.get("/people/non_existent_cluster/thumbnail.jpg")
        self.assertEqual(res.status_code, 404)


if __name__ == "__main__":
    unittest.main()
