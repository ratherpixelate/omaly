import cv2
import numpy as np
from fastapi import APIRouter, HTTPException
from .common import db, resolve_path

router = APIRouter()
_cache: dict = {}


def _sharpness(path) -> float:
    if path is None:
        return 0.0
    data = np.fromfile(str(path), dtype=np.uint8)   # safe for spaces/non-ASCII paths on Windows
    img = cv2.imdecode(data, cv2.IMREAD_GRAYSCALE)
    if img is None:
        return 0.0
    s = 800 / max(img.shape)
    if s < 1:
        img = cv2.resize(img, None, fx=s, fy=s, interpolation=cv2.INTER_AREA)
    return float(cv2.Laplacian(img, cv2.CV_64F).var())


def pick_best(group_id: str):
    with db() as c:
        rows = c.execute(
            "SELECT id, filepath FROM photos WHERE burst_group_id=? ORDER BY id", (group_id,)
        ).fetchall()
    if not rows:
        return None
    key = (group_id, len(rows))
    if key not in _cache:
        scores = {r["id"]: _sharpness(resolve_path(r["filepath"])) for r in rows}
        _cache[key] = {
            "group_id": group_id,
            "best_photo_id": max(scores, key=scores.get),
            "candidates": [r["id"] for r in rows],
        }
    return _cache[key]


@router.get("/best-shot")
def best_shot_endpoint(group_id: str):
    res = pick_best(group_id)
    if not res:
        raise HTTPException(404, "unknown burst group")
    return res