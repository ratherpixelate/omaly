"""GET /wrapped -- Spotify-Wrapped-style annual recap of people, places, pets, and best shots.

Aggregates real statistics from SQLite:
- Year & photos taken in that year
- Top 3 persons
- Most visited places (if location data is available)
- Statistics object: total photos, most photos taken in a day, most visited location,
  most photos with a person, and busiest month.
- 2-3 sentence narrative via local Ollama (phi3:mini) with deterministic fallback.
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
_cached_year = None


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


def _compute_wrapped_data(c, year: int | None = None) -> dict:
    """Query real database tables to build wrapped aggregations and statistics."""
    # 1. Determine target year
    if year is None:
        yr_row = c.execute(
            "SELECT SUBSTR(taken_at, 1, 4) AS yr, COUNT(*) as cnt "
            "FROM photos WHERE taken_at IS NOT NULL GROUP BY yr "
            "ORDER BY cnt DESC LIMIT 1"
        ).fetchone()
        year = int(yr_row[0]) if yr_row and yr_row[0] else datetime.now().year

    year_prefix = f"{year}%"

    # 2. Photos taken in that year
    year_photos = c.execute(
        "SELECT id FROM photos WHERE taken_at LIKE ? ORDER BY taken_at",
        (year_prefix,)
    ).fetchall()
    photos_in_year = [r[0] for r in year_photos]
    total_in_year = len(photos_in_year)

    # Total photos fallback if no date tags match
    total_photos = total_in_year if total_in_year > 0 else c.execute("SELECT COUNT(*) FROM photos").fetchone()[0]

    # 3. Top 3 people
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

    # 4. Most visited places (top locations)
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

    # 5. Statistics:
    # - most photos taken in a day
    day_row = c.execute(
        "SELECT SUBSTR(taken_at, 1, 10) as day, COUNT(*) as cnt FROM photos "
        "WHERE taken_at LIKE ? GROUP BY day ORDER BY cnt DESC LIMIT 1",
        (year_prefix,)
    ).fetchone()
    most_photos_day = None
    if day_row and day_row[0]:
        d_str = day_row[0]
        try:
            f_date = datetime.strptime(d_str, "%Y-%m-%d").strftime("%B %d, %Y")
        except Exception:
            f_date = d_str
        most_photos_day = {
            "date": d_str,
            "formatted_date": f_date,
            "photo_count": int(day_row[1]),
            "count": int(day_row[1]),
        }

    # - busiest month
    month_row = c.execute(
        "SELECT SUBSTR(taken_at, 1, 7) as m, COUNT(*) as cnt FROM photos "
        "WHERE taken_at LIKE ? GROUP BY m ORDER BY cnt DESC LIMIT 1",
        (year_prefix,)
    ).fetchone()
    busiest_month = None
    if month_row and month_row[0]:
        m_str = month_row[0]
        try:
            f_month = datetime.strptime(m_str, "%Y-%m").strftime("%B %Y")
        except Exception:
            f_month = m_str
        busiest_month = {
            "month": m_str,
            "formatted_month": f_month,
            "photo_count": int(month_row[1]),
            "count": int(month_row[1]),
        }

    # - most visited location
    most_visited_location = top_locations[0] if top_locations else None

    # - most photos with a person
    most_photos_person = top_people[0] if top_people else None

    statistics = {
        "total_photos": total_photos,
        "most_photos_taken_in_a_day": most_photos_day,
        "most_visited_location": most_visited_location,
        "most_photos_with_a_person": most_photos_person,
        "busiest_month": busiest_month,
    }

    # 6. Pets detected
    pet_row = c.execute(
        "SELECT 1 FROM photos WHERE object_tags LIKE ? OR object_tags LIKE ? LIMIT 1",
        ('%"dog"%', '%"cat"%')
    ).fetchone()
    pets_detected = bool(pet_row)

    # 7. Burst groups
    burst_groups = [r[0] for r in c.execute(
        "SELECT DISTINCT burst_group_id FROM photos "
        "WHERE burst_group_id IS NOT NULL ORDER BY burst_group_id"
    ).fetchall()]

    return {
        "year": year,
        "photos_in_year": photos_in_year,
        "photos_taken_in_year": photos_in_year,
        "total_photos": total_photos,
        "top_people": top_people,
        "top_locations": top_locations,
        "statistics": statistics,
        "pets_detected": pets_detected,
        "burst_groups": burst_groups,
    }


def warmup():
    """Background task to pre-load Ollama model and pre-generate the narrative."""
    global _cached_narrative, _cached_year
    try:
        with db() as c:
            data = _compute_wrapped_data(c)

        year = data["year"]
        total = data["total_photos"]
        stats = data["statistics"]
        top_people = data["top_people"]
        pets_detected = data["pets_detected"]

        people_names = ", ".join(f"{p['label']} ({p['photo_count']} photos)" for p in top_people) if top_people else "None recorded"
        day_str = f"{stats['most_photos_taken_in_a_day']['formatted_date']} ({stats['most_photos_taken_in_a_day']['count']} photos)" if stats['most_photos_taken_in_a_day'] else "N/A"
        month_str = f"{stats['busiest_month']['formatted_month']} ({stats['busiest_month']['count']} photos)" if stats['busiest_month'] else "N/A"

        prompt = (
            f"You are writing a short, exciting Spotify-Wrapped-style photo recap for {year}. "
            "In exactly two friendly, complete sentences, summarize these statistics (no markdown, no bullet points):\n"
            f"- Total photos: {total}\n"
            f"- Busiest day: {day_str}\n"
            f"- Busiest month: {month_str}\n"
            f"- Top people: {people_names}\n"
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
                "options": {"temperature": 0.3, "num_predict": 75}
            }).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=60) as resp:
            resp_data = json.loads(resp.read().decode("utf-8"))
            nar = _clean_narrative(resp_data.get("response", ""))
            if nar and len(nar) > 20:
                _cached_narrative = nar
                _cached_year = year
                print(f"[wrapped] Ollama narrative pre-generated: {_cached_narrative}")
    except Exception as e:
        print(f"[wrapped] Ollama warmup note: {e}")


def _generate_narrative(year: int, total_photos: int, stats: dict, top_people: list[dict],
                        top_locations: list[dict], pets_detected: bool) -> str:
    global _cached_narrative, _cached_year
    if _cached_narrative and _cached_year == year:
        return _cached_narrative

    # Deterministic fallback template if Ollama is unreachable
    person_text = f", spending the most time with {stats['most_photos_with_a_person']['label']}" if stats.get("most_photos_with_a_person") else ""
    day_text = f", peaking on {stats['most_photos_taken_in_a_day']['formatted_date']}" if stats.get("most_photos_taken_in_a_day") else ""
    loc_text = f" across {len(top_locations)} places" if top_locations else ""
    pet_text = ", along with your favorite pets" if pets_detected else ""
    fallback = (
        f"You captured {total_photos} memories in {year}"
        f"{person_text}{loc_text}{day_text}{pet_text}."
    )

    # Attempt local Ollama generation
    people_names = ", ".join(f"{p['label']} ({p['photo_count']} photos)" for p in top_people) if top_people else "None recorded"
    day_str = f"{stats['most_photos_taken_in_a_day']['formatted_date']} ({stats['most_photos_taken_in_a_day']['count']} photos)" if stats.get('most_photos_taken_in_a_day') else "N/A"
    month_str = f"{stats['busiest_month']['formatted_month']} ({stats['busiest_month']['count']} photos)" if stats.get('busiest_month') else "N/A"

    prompt = (
        f"You are writing a short, exciting Spotify-Wrapped-style photo recap for {year}. "
        "In exactly two friendly, complete sentences, summarize these statistics (no markdown, no bullet points):\n"
        f"- Total photos: {total_photos}\n"
        f"- Busiest day: {day_str}\n"
        f"- Busiest month: {month_str}\n"
        f"- Top people: {people_names}\n"
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
                "options": {"temperature": 0.3, "num_predict": 75}
            }).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=OLLAMA_TIMEOUT_S) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            nar = _clean_narrative(data.get("response", ""))
            if nar and len(nar) > 20:
                _cached_narrative = nar
                _cached_year = year
                return _cached_narrative
    except Exception as e:
        print(f"[wrapped] Ollama live generation note: {e}")

    return fallback


@router.get("/wrapped")
def wrapped(year: int | None = None):
    with db() as c:
        data = _compute_wrapped_data(c, year=year)

    best_shots = []
    for gid in data["burst_groups"][:5]:
        res = pick_best(gid)
        if res and res.get("best_photo_id"):
            best_shots.append(res["best_photo_id"])

    narrative = _generate_narrative(
        year=data["year"],
        total_photos=data["total_photos"],
        stats=data["statistics"],
        top_people=data["top_people"],
        top_locations=data["top_locations"],
        pets_detected=data["pets_detected"]
    )

    return {
        "year": data["year"],
        "total_photos": data["total_photos"],
        "photos_in_year": data["photos_in_year"],
        "photos_taken_in_year": data["photos_taken_in_year"],
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "top_people": data["top_people"],
        "top_locations": data["top_locations"],
        "statistics": data["statistics"],
        "pets_detected": data["pets_detected"],
        "best_shots": best_shots,
        "narrative": narrative,
    }