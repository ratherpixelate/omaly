"""API routes for face clusters and people collections:
- GET  /people                   -> List all face clusters with zoomed-in face cover thumbnails
- GET  /people/{cluster_id}/photos -> Photos featuring a given person
- GET  /people/{cluster_id}/thumbnail.jpg -> Zoomed-in cropped face portrait thumbnail
- POST /people/{cluster_id}/rename -> Rename a person (persists in SQLite)
- PUT  /people/{cluster_id}        -> Alias for rename
"""
import os
import shutil
import urllib.parse
from pathlib import Path
from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel
from PIL import Image

from .common import db, resolve_path, THUMB_DIR, BASE

router = APIRouter(prefix="/people", tags=["people"])

PEOPLE_THUMB_DIR = THUMB_DIR / "people"
PEOPLE_THUMB_DIR.mkdir(parents=True, exist_ok=True)
DEBUG_CROPS_DIR = BASE / "data" / "debug" / "crops"


class RenamePersonRequest(BaseModel):
    name: str


def _format_name(cluster_id: str, label: str | None) -> str:
    if label and label.strip():
        return label.strip()
    clean_num = cluster_id.replace("p", "").strip()
    return f"Person {clean_num}" if clean_num.isdigit() else f"Person {cluster_id}"


def get_person_face_thumbnail(cluster_id: str) -> Path | None:
    """Retrieve or generate a tightly cropped, zoomed-in face avatar for a cluster."""
    cached_path = PEOPLE_THUMB_DIR / f"{cluster_id}.jpg"
    if cached_path.exists() and cached_path.stat().st_size > 0:
        return cached_path

    # Check pre-computed debug crops
    debug_crop = DEBUG_CROPS_DIR / f"{cluster_id}_0.jpg"
    if debug_crop.exists() and debug_crop.stat().st_size > 0:
        try:
            shutil.copyfile(debug_crop, cached_path)
            return cached_path
        except Exception:
            return debug_crop

    # On-demand face crop generation from photo row
    with db() as c:
        photo_row = c.execute(
            "SELECT id, filepath FROM photos "
            "WHERE face_cluster_ids LIKE ? ORDER BY taken_at ASC, id ASC LIMIT 1",
            (f'%"{cluster_id}"%',),
        ).fetchone()

    if not photo_row:
        return None

    resolved_path = resolve_path(photo_row["filepath"]) or Path(photo_row["filepath"])
    if not resolved_path.exists():
        # Fall back to photo thumbnail if source photo missing
        fallback_thumb = THUMB_DIR / f"{photo_row['id']}.jpg"
        return fallback_thumb if fallback_thumb.exists() else None

    try:
        from ingestion import load_rgb
        from ingestion.faces import detect_all, MAX_SIDE

        clean_img = load_rgb(resolved_path, MAX_SIDE)
        faces, _ = detect_all([(photo_row["id"], resolved_path)])

        if faces:
            # Find the best face (or the largest face if cluster tag isn't yet set)
            target = max(faces, key=lambda f: (f["bbox"][2] - f["bbox"][0]) * (f["bbox"][3] - f["bbox"][1]))
            x1, y1, x2, y2 = target["bbox"]
            pad = 0.22 * max(x2 - x1, y2 - y1)
            crop = clean_img.crop((
                max(0, x1 - pad),
                max(0, y1 - pad),
                min(clean_img.width, x2 + pad),
                min(clean_img.height, y2 + pad)
            ))
            crop.thumbnail((240, 240), Image.Resampling.LANCZOS)
            crop.save(cached_path, quality=92)
            return cached_path
    except Exception as e:
        print(f"[people] Face crop on-demand note for {cluster_id}: {e}")

    # Ultimate fallback to whole photo thumbnail
    fallback_thumb = THUMB_DIR / f"{photo_row['id']}.jpg"
    return fallback_thumb if fallback_thumb.exists() else None


@router.get("/{cluster_id}/thumbnail.jpg")
@router.get("/{cluster_id}/thumbnail")
def get_person_thumbnail(cluster_id: str):
    """Serve a tightly cropped portrait face thumbnail for a person cluster."""
    path = get_person_face_thumbnail(cluster_id)
    if not path or not path.exists():
        raise HTTPException(
            status_code=404, detail=f"Thumbnail for cluster '{cluster_id}' not found"
        )
    return FileResponse(path, media_type="image/jpeg")


@router.get("")
def list_people():
    """List all detected face clusters with zoomed-in face thumbnails, names, and counts."""
    with db() as c:
        raw_clusters = c.execute(
            "SELECT cluster_id, label, photo_count FROM face_clusters "
            "WHERE photo_count >= 1 ORDER BY photo_count DESC, cluster_id ASC"
        ).fetchall()

        people = []
        for r in raw_clusters:
            cid = r["cluster_id"]
            label = r["label"]
            count = int(r["photo_count"])

            photo_row = c.execute(
                "SELECT id, filename FROM photos "
                "WHERE face_cluster_ids LIKE ? ORDER BY taken_at ASC, id ASC LIMIT 1",
                (f'%"{cid}"%',),
            ).fetchone()

            cover_photo_id = photo_row["id"] if photo_row else None
            # Provide zoomed-in face thumbnail
            thumb_url = f"/people/{cid}/thumbnail.jpg"

            people.append(
                {
                    "id": cid,
                    "name": _format_name(cid, label),
                    "photo_count": count,
                    "cover_photo_id": cover_photo_id,
                    "thumbnail_url": thumb_url,
                }
            )

        return {"people": people}


@router.get("/{cluster_id}/photos")
def get_person_photos(cluster_id: str):
    """Return all photos featuring a given person cluster."""
    with db() as c:
        cluster = c.execute(
            "SELECT cluster_id, label, photo_count FROM face_clusters WHERE cluster_id = ?",
            (cluster_id,),
        ).fetchone()

        if not cluster:
            raise HTTPException(
                status_code=404, detail=f"Person cluster '{cluster_id}' not found"
            )

        rows = c.execute(
            "SELECT id, filename, taken_at FROM photos "
            "WHERE face_cluster_ids LIKE ? ORDER BY taken_at DESC, id ASC",
            (f'%"{cluster_id}"%',),
        ).fetchall()

        photos = []
        for r in rows:
            fn = r["filename"]
            photos.append(
                {
                    "id": r["id"],
                    "name": fn,
                    "filename": fn,
                    "url": "/files/" + urllib.parse.quote(fn),
                    "thumbnail_url": f"/thumbnails/{r['id']}.jpg",
                    "taken_at": r["taken_at"],
                    "type": "photo",
                }
            )

        return {
            "cluster_id": cluster_id,
            "name": _format_name(cluster_id, cluster["label"]),
            "photo_count": len(photos),
            "thumbnail_url": f"/people/{cluster_id}/thumbnail.jpg",
            "photos": photos,
        }


@router.post("/{cluster_id}/rename")
@router.put("/{cluster_id}")
def rename_person(cluster_id: str, req: RenamePersonRequest):
    """Rename a face cluster in SQLite."""
    new_name = req.name.strip()
    if not new_name:
        raise HTTPException(status_code=400, detail="Name cannot be empty")

    with db() as c:
        cluster = c.execute(
            "SELECT cluster_id, photo_count FROM face_clusters WHERE cluster_id = ?",
            (cluster_id,),
        ).fetchone()

        if not cluster:
            raise HTTPException(
                status_code=404, detail=f"Person cluster '{cluster_id}' not found"
            )

        c.execute(
            "UPDATE face_clusters SET label = ? WHERE cluster_id = ?",
            (new_name, cluster_id),
        )
        c.commit()
        photo_row = c.execute(
            "SELECT id, filename FROM photos "
            "WHERE face_cluster_ids LIKE ? ORDER BY taken_at ASC, id ASC LIMIT 1",
            (f'%"{cluster_id}"%',),
        ).fetchone()

        cover_photo_id = photo_row["id"] if photo_row else None
        thumb_url = f"/people/{cluster_id}/thumbnail.jpg"

        return {
            "id": cluster_id,
            "name": new_name,
            "photo_count": int(cluster["photo_count"]),
            "cover_photo_id": cover_photo_id,
            "thumbnail_url": thumb_url,
        }
