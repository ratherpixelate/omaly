"""GET /wrapped -- Spotify-Wrapped-style annual recap of people, places, and statistics.

Aggregates real statistics from SQLite:
- Year & photos taken in that year
- Top 3 persons with cover photo thumbnails
- Most visited places (if location data is available) with cover thumbnails
- Statistics object: total photos, most photos taken in a day, most visited location,
  most photos with a person, and busiest month.
- Deterministic, fast recap narrative generated on-device with zero external dependencies.
"""
from datetime import datetime
from fastapi import APIRouter
from .common import db
from .best_shot import pick_best

router = APIRouter()


def _format_person_name(cluster_id: str, label: str | None) -> str:
    if label and label.strip():
        return label.strip()
    clean_num = cluster_id.replace("p", "").strip()
    return f"Person {clean_num}" if clean_num.isdigit() else f"Person {cluster_id}"


def _compute_wrapped_data(c, year: int | None = None) -> dict:
    """Query real database tables to build wrapped aggregations and statistics."""
    # 1. Determine target year and available years
    available_years = [int(r[0]) for r in c.execute(
        "SELECT DISTINCT SUBSTR(taken_at, 1, 4) FROM photos "
        "WHERE taken_at IS NOT NULL AND SUBSTR(taken_at, 1, 4) GLOB '[0-9][0-9][0-9][0-9]' "
        "ORDER BY SUBSTR(taken_at, 1, 4) DESC"
    ).fetchall()]

    if year is None:
        yr_row = c.execute(
            "SELECT SUBSTR(taken_at, 1, 4) AS yr, COUNT(*) as cnt "
            "FROM photos WHERE taken_at IS NOT NULL GROUP BY yr "
            "ORDER BY cnt DESC LIMIT 1"
        ).fetchone()
        year = int(yr_row[0]) if yr_row and yr_row[0] else (available_years[0] if available_years else datetime.now().year)

    year_prefix = f"{year}%"

    # 2. Photos taken in that year
    year_photos = c.execute(
        "SELECT id FROM photos WHERE taken_at LIKE ? ORDER BY taken_at",
        (year_prefix,)
    ).fetchall()
    photos_in_year = [r[0] for r in year_photos]

    # Total photos fallback if no date tags match
    total_in_year = len(photos_in_year)
    total_db_photos = c.execute("SELECT COUNT(*) FROM photos").fetchone()[0]
    total_photos = total_in_year if total_in_year > 0 else total_db_photos

    if not photos_in_year:
        all_photos = c.execute("SELECT id FROM photos ORDER BY taken_at ASC, id ASC LIMIT 50").fetchall()
        photos_in_year = [r[0] for r in all_photos]

    # 3. Top 3 people with cover thumbnails
    raw_people = c.execute(
        "SELECT cluster_id, label, photo_count FROM face_clusters "
        "WHERE photo_count >= 1 ORDER BY photo_count DESC, cluster_id ASC LIMIT 3"
    ).fetchall()
    top_people = []
    for r in raw_people:
        cid = r["cluster_id"]
        label = _format_person_name(cid, r["label"])
        count = int(r["photo_count"])

        # Fetch representative photo for this person
        photo_row = c.execute(
            "SELECT id FROM photos WHERE face_cluster_ids LIKE ? ORDER BY taken_at ASC, id ASC LIMIT 1",
            (f'%"{cid}"%',),
        ).fetchone()
        cover_id = photo_row["id"] if photo_row else None
        thumb_url = f"/thumbnails/{cover_id}.jpg" if cover_id else None

        top_people.append({
            "cluster_id": cid,
            "label": label,
            "photo_count": count,
            "cover_photo_id": cover_id,
            "thumbnail_url": thumb_url,
        })

    # 4. Most visited places (top locations) with cover thumbnails
    raw_locs = c.execute(
        "SELECT ROUND(latitude, 2) AS lat, ROUND(longitude, 2) AS lon, "
        "COUNT(*) AS photo_count FROM photos "
        "WHERE latitude IS NOT NULL AND longitude IS NOT NULL "
        "GROUP BY lat, lon ORDER BY photo_count DESC LIMIT 3"
    ).fetchall()
    top_locations = []
    for r in raw_locs:
        lat = float(r["lat"])
        lon = float(r["lon"])
        count = int(r["photo_count"])

        # Fetch representative photo taken at this location
        loc_row = c.execute(
            "SELECT id FROM photos "
            "WHERE ROUND(latitude, 2) = ? AND ROUND(longitude, 2) = ? LIMIT 1",
            (lat, lon)
        ).fetchone()
        loc_photo_id = loc_row["id"] if loc_row else None
        loc_thumb = f"/thumbnails/{loc_photo_id}.jpg" if loc_photo_id else None

        top_locations.append({
            "name": f"{lat:.2f}, {lon:.2f}",
            "lat": lat,
            "lon": lon,
            "photo_count": count,
            "cover_photo_id": loc_photo_id,
            "thumbnail_url": loc_thumb,
        })

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

    # - most active time of day (calculated from real timestamps)
    hours = [int(r[0][11:13]) for r in c.execute(
        "SELECT taken_at FROM photos WHERE taken_at LIKE ? AND LENGTH(taken_at) >= 13",
        (year_prefix,)
    ).fetchall()]
    most_active_time = None
    if hours:
        slots = {
            "Morning (6 AM – 12 PM)": sum(1 for h in hours if 6 <= h < 12),
            "Afternoon (12 PM – 5 PM)": sum(1 for h in hours if 12 <= h < 17),
            "Evening (5 PM – 9 PM)": sum(1 for h in hours if 17 <= h < 21),
            "Late Night (9 PM – 2 AM)": sum(1 for h in hours if h >= 21 or h < 2),
            "Early Hours (2 AM – 6 AM)": sum(1 for h in hours if 2 <= h < 6),
        }
        best_slot, best_count = max(slots.items(), key=lambda x: x[1])
        if best_count > 0:
            most_active_time = f"{best_slot} ({best_count} photos)"

    # - burst groups in this year
    burst_groups = [r[0] for r in c.execute(
        "SELECT DISTINCT burst_group_id FROM photos "
        "WHERE burst_group_id IS NOT NULL AND taken_at LIKE ? ORDER BY burst_group_id",
        (year_prefix,)
    ).fetchall()]

    # - most visited location (only if real GPS data exists)
    most_visited_location = top_locations[0] if top_locations else None

    # - most photos with a person
    most_photos_person = top_people[0] if top_people else None

    statistics = {
        "total_photos": total_photos,
        "most_photos_taken_in_a_day": most_photos_day,
        "most_visited_location": most_visited_location,
        "most_photos_with_a_person": most_photos_person,
        "busiest_month": busiest_month,
        "most_active_time": most_active_time,
        "burst_groups_count": len(burst_groups),
    }

    # 6. Pets detected
    pet_row = c.execute(
        "SELECT 1 FROM photos WHERE object_tags LIKE ? OR object_tags LIKE ? LIMIT 1",
        ('%"dog"%', '%"cat"%')
    ).fetchone()
    pets_detected = bool(pet_row)

    return {
        "year": year,
        "available_years": available_years,
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
    """No-op warmup for backward compatibility (Ollama is decoupled)."""
    pass


def _generate_narrative(year: int, total_photos: int, stats: dict, top_people: list[dict],
                        top_locations: list[dict], pets_detected: bool) -> str:
    """Instant deterministic recap narrative generated on-device."""
    person_text = f", spending the most time with {stats['most_photos_with_a_person']['label']}" if stats.get("most_photos_with_a_person") else ""
    day_text = f", peaking on {stats['most_photos_taken_in_a_day']['formatted_date']}" if stats.get("most_photos_taken_in_a_day") else ""
    loc_text = f" across {len(top_locations)} places" if top_locations else ""
    pet_text = ", along with your favorite pets" if pets_detected else ""
    return (
        f"You captured {total_photos} memories in {year}"
        f"{person_text}{loc_text}{day_text}{pet_text}."
    )


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
        "available_years": data.get("available_years", [data["year"]]),
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