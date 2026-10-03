"""GET /wrapped -- Spotify-Wrapped-style annual recap of people, places, pets, and best shots.

Aggregates real statistics from SQLite and generates a 2-3 sentence narrative
via local Ollama (phi3:mini). Includes deterministic fallback if Ollama is
unavailable or times out.
"""
import json
import os
import urllib.request
from datetime import datetime
from fastapi import APIRouter
from .common import db
from .best_shot import pick_best

router = APIRouter()

OLLAMA_URL = os.getenv("OMALY_OLLAMA_URL", "http://localhost:11434/api/generate")
OLLAMA_MODEL = os.getenv("OMALY_OLLAMA_MODEL", "phi3:mini")
OLLAMA_TIMEOUT_S = 18.0


_cached_narrative = None


def _clean_narrative(text: str) -> str:
    """Trim markdown and ensure narrative cleanly terminates at punctuation."""
    if not text:
        return ""
    text = text.strip('"\'*# \n')
    last_punct = max(text.rfind('.'), text.rfind('!'))
    if last_punct > 25:
        text = text[:last_punct + 1]
    elif text and not text.endswith(('.', '!')):
        text += '.'
    return text


def warmup():
    """Background task to pre-load Ollama model and pre-generate the narrative."""
    global _cached_narrative
    try:
        with db() as c:
            total = c.execute("SELECT COUNT(*) FROM photos").fetchone()[0]
            raw_people = c.execute(
                "SELECT cluster_id, label, photo_count FROM face_clusters "
                "WHERE photo_count >= 2 ORDER BY photo_count DESC LIMIT 3"
            ).fetchall()
            top_people = [
                {"label": r["label"] or f"Person {r['cluster_id'].replace('p', '')}",
                 "photo_count": int(r["photo_count"])}
                for r in raw_people
            ]
            loc_count = c.execute(
                "SELECT COUNT(DISTINCT ROUND(latitude, 2) || ',' || ROUND(longitude, 2)) "
                "FROM photos WHERE latitude IS NOT NULL AND longitude IS NOT NULL"
            ).fetchone()[0]
            pet_row = c.execute(
                "SELECT 1 FROM photos WHERE object_tags LIKE ? OR object_tags LIKE ? LIMIT 1",
                ('%"dog"%', '%"cat"%')
            ).fetchone()
            pets_detected = bool(pet_row)

        people_names = ", ".join(f"{p['label']} ({p['photo_count']} photos)" for p in top_people) if top_people else "None recorded"
        prompt = (
            "You are an annual photo recap narrator (Spotify Wrapped style). In exactly two friendly, "
            "complete sentences, summarize these photo statistics (no markdown, no bullet points):\n"
            f"- Total photos: {total}\n"
            f"- Top people: {people_names}\n"
            f"- Locations: {loc_count} locations\n"
            f"- Pets detected: {'Yes' if pets_detected else 'No'}\n"
            "Recap:"
        )

        req = urllib.request.Request(
            OLLAMA_URL,
            data=json.dumps({
                "model": OLLAMA_MODEL,
                "prompt": prompt,
                "stream": False,
                "keep_alive": -1,
                "options": {"temperature": 0.3, "num_predict": 90}
            }).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            nar = _clean_narrative(data.get("response", ""))
            if nar and len(nar) > 20:
                _cached_narrative = nar
                print(f"[wrapped] Ollama narrative pre-generated: {_cached_narrative}")
    except Exception as e:
        print(f"[wrapped] Ollama warmup note: {e}")


def _generate_narrative(total_photos: int, top_people: list[dict],
                        top_locations: list[dict], pets_detected: bool) -> str:
    global _cached_narrative
    if _cached_narrative:
        return _cached_narrative

    # Deterministic fallback template if Ollama is unreachable
    person_text = f", spending the most time with {top_people[0]['label']}" if top_people else ""
    loc_text = f" across {len(top_locations)} places" if top_locations else " in your favorite spots"
    pet_text = ", along with your favorite pets" if pets_detected else ""
    fallback = (
        f"You captured {total_photos} memories this year"
        f"{person_text}{loc_text}{pet_text}."
    )

    # Attempt local Ollama generation
    people_names = ", ".join(f"{p['label']} ({p['photo_count']} photos)" for p in top_people) if top_people else "None recorded"
    prompt = (
        "You are an annual photo recap narrator (Spotify Wrapped style). In exactly two friendly, "
        "complete sentences, summarize these photo statistics (no markdown, no bullet points):\n"
        f"- Total photos: {total_photos}\n"
        f"- Top people: {people_names}\n"
        f"- Locations: {len(top_locations)} locations\n"
        f"- Pets detected: {'Yes' if pets_detected else 'No'}\n"
        "Recap:"
    )

    try:
        req = urllib.request.Request(
            OLLAMA_URL,
            data=json.dumps({
                "model": OLLAMA_MODEL,
                "prompt": prompt,
                "stream": False,
                "keep_alive": -1,
                "options": {"temperature": 0.3, "num_predict": 90}
            }).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=OLLAMA_TIMEOUT_S) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            nar = _clean_narrative(data.get("response", ""))
            if nar and len(nar) > 20:
                _cached_narrative = nar
                return _cached_narrative
    except Exception as e:
        print(f"[wrapped] Ollama live generation note: {e}")

    return fallback


@router.get("/wrapped")
def wrapped():
    with db() as c:
        total_photos = c.execute("SELECT COUNT(*) FROM photos").fetchone()[0]

        # top_people: top 3 face clusters with photo_count >= 2
        raw_people = c.execute(
            "SELECT cluster_id, label, photo_count FROM face_clusters "
            "WHERE photo_count >= 2 ORDER BY photo_count DESC LIMIT 3"
        ).fetchall()
        top_people = [
            {
                "cluster_id": r["cluster_id"],
                "label": r["label"] or f"Person {r['cluster_id'].replace('p', '')}",
                "photo_count": int(r["photo_count"]),
            }
            for r in raw_people
        ]

        # top_locations: top 3 clusters rounded to 2 decimal places
        raw_locs = c.execute(
            "SELECT ROUND(latitude, 2) AS lat, ROUND(longitude, 2) AS lon, "
            "COUNT(*) AS photo_count FROM photos "
            "WHERE latitude IS NOT NULL AND longitude IS NOT NULL "
            "GROUP BY lat, lon ORDER BY photo_count DESC LIMIT 3"
        ).fetchall()
        top_locations = [
            {
                "name": f"{float(r['lat']):.2f}, {float(r['lon']):.2f}",
                "lat": float(r["lat"]),
                "lon": float(r["lon"]),
                "photo_count": int(r["photo_count"]),
            }
            for r in raw_locs
        ]

        # pets_detected: check for dog or cat in object_tags
        pet_row = c.execute(
            "SELECT 1 FROM photos WHERE object_tags LIKE ? OR object_tags LIKE ? LIMIT 1",
            ('%"dog"%', '%"cat"%')
        ).fetchone()
        pets_detected = bool(pet_row)

        # best_shots: top photo from each burst group, capped at 5
        burst_groups = [r[0] for r in c.execute(
            "SELECT DISTINCT burst_group_id FROM photos "
            "WHERE burst_group_id IS NOT NULL ORDER BY burst_group_id"
        ).fetchall()]

    best_shots = []
    for gid in burst_groups[:5]:
        res = pick_best(gid)
        if res and res.get("best_photo_id"):
            best_shots.append(res["best_photo_id"])

    narrative = _generate_narrative(total_photos, top_people, top_locations, pets_detected)

    return {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "top_people": top_people,
        "top_locations": top_locations,
        "pets_detected": pets_detected,
        "best_shots": best_shots,
        "narrative": narrative,
    }