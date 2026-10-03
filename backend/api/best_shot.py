"""GET /best-shot -- pick the top 1-2 photos of a burst group.

Reads the group's photos from omaly.db and scores them with
ingestion.quality (person-relative closed-eye detection + clarity).
Metrics are computed on first request and cached per photo in the
photo_quality table; repeat calls are a fast SQL read.

    GET /best-shot?group_id=b_9d9a2f55&top_k=2

top_k is an optional override (1 or 2). By default the endpoint is
adaptive: it returns 2 candidates only when the runner-up is in the
same blink tier as the winner and scores within quality.ADAPTIVE_MARGIN
of the winner (nearly as good, hard to call), otherwise just the winner.

Response keeps the frontend contract ({group_id, best_photo_id,
candidates}) and adds a `scores` breakdown for debugging; extra keys are
ignored by the Dart model.
"""
import urllib.parse
from fastapi import APIRouter, HTTPException, Query

from ingestion import quality
from .common import db, resolve_path

router = APIRouter()


@router.get("/best-shot")
def best_shot_endpoint(group_id: str = Query(..., min_length=1),
                       top_k: int | None = Query(None, ge=1, le=2)):
    with db() as con:
        raw_rows = con.execute(
            "SELECT id, filepath, taken_at, face_cluster_ids FROM photos "
            "WHERE burst_group_id=? ORDER BY taken_at", (group_id,)).fetchall()
        if not raw_rows:
            raise HTTPException(
                status_code=404,
                detail=f"no burst group {group_id!r} in the database",
            )
        rows = [
            (r["id"], str(resolve_path(r["filepath"]) or r["filepath"]),
             r["taken_at"], r["face_cluster_ids"])
            for r in raw_rows
        ]
        results = quality.rank_group(con, rows)

    scored = [r for r in results if r["score"] is not None]
    if not scored:
        raise HTTPException(
            status_code=422,
            detail=f"burst {group_id}: no photo could be scored "
                   f"({results[0]['error']})",
        )

    effective_top_k = top_k if isinstance(top_k, int) else None
    if effective_top_k is None:  # adaptive: 2 only when runner-up is in the same blink tier and nearly as good
        n = 1
        if len(scored) > 1:
            winner, runner_up = scored[0], scored[1]
            same_tier = winner.get("blink_tier", 0) == runner_up.get("blink_tier", 0)
            close_score = runner_up["score"] >= winner["score"] - quality.ADAPTIVE_MARGIN
            if same_tier and close_score:
                n = 2
    else:
        n = min(effective_top_k, len(scored))

    return {
        "group_id": group_id,
        "best_photo_id": scored[0]["photo_id"],
        "candidates": [r["photo_id"] for r in scored[:n]],
        "scores": [{k: v for k, v in r.items() if k != "faces"} for r in results],
    }


@router.get("/bursts")
def list_bursts():
    """List all burst groups with their photos and ranked best shot."""
    with db() as con:
        burst_ids = [
            r[0]
            for r in con.execute(
                "SELECT DISTINCT burst_group_id FROM photos "
                "WHERE burst_group_id IS NOT NULL ORDER BY burst_group_id"
            ).fetchall()
        ]

        bursts = []
        for gid in burst_ids:
            raw_rows = con.execute(
                "SELECT id, filepath, filename, taken_at, face_cluster_ids FROM photos "
                "WHERE burst_group_id=? ORDER BY taken_at",
                (gid,),
            ).fetchall()
            if not raw_rows:
                continue

            rows = [
                (
                    r["id"],
                    str(resolve_path(r["filepath"]) or r["filepath"]),
                    r["taken_at"],
                    r["face_cluster_ids"],
                )
                for r in raw_rows
            ]
            results = quality.rank_group(con, rows)
            scored = [r for r in results if r.get("score") is not None]
            best_id = scored[0]["photo_id"] if scored else raw_rows[0]["id"]

            candidates = [best_id]
            if len(scored) > 1:
                winner, runner_up = scored[0], scored[1]
                same_tier = winner.get("blink_tier", 0) == runner_up.get("blink_tier", 0)
                close_score = runner_up["score"] >= winner["score"] - quality.ADAPTIVE_MARGIN
                if same_tier and close_score:
                    candidates.append(runner_up["photo_id"])

            filename_map = {r["id"]: r["filename"] for r in raw_rows}

            photos_list = []
            for rank, r in enumerate(results, start=1):
                pid = r["photo_id"]
                fn = filename_map.get(pid, r.get("filename", ""))
                photos_list.append(
                    {
                        "id": pid,
                        "filename": fn,
                        "name": fn,
                        "url": f"/files/{urllib.parse.quote(fn)}",
                        "thumbnail_url": f"/thumbnails/{pid}.jpg",
                        "taken_at": r.get("taken_at"),
                        "is_best": pid == best_id,
                        "is_candidate": pid in candidates,
                        "rank": rank,
                        "score": round(r["score"], 4) if r.get("score") is not None else None,
                        "blink_tier": r.get("blink_tier"),
                        "n_faces": r.get("n_faces"),
                        "n_closed": r.get("n_closed"),
                        "eyes_openness": round(r["eyes"], 4) if r.get("eyes") is not None else None,
                        "sharpness": round(r["sharpness"], 4) if r.get("sharpness") is not None else None,
                    }
                )

            bursts.append(
                {
                    "group_id": gid,
                    "photo_count": len(raw_rows),
                    "best_photo_id": best_id,
                    "candidates": candidates,
                    "photos": photos_list,
                }
            )

        return {"bursts": bursts}


def pick_best(group_id: str):
    """Compatibility helper for internal callers expecting pick_best()."""
    try:
        return best_shot_endpoint(group_id=group_id)
    except HTTPException:
        return None
