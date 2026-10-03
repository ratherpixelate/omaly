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

    if top_k is None:  # adaptive: 2 only when runner-up is in the same blink tier and nearly as good
        n = 1
        if len(scored) > 1:
            winner, runner_up = scored[0], scored[1]
            same_tier = winner.get("blink_tier", 0) == runner_up.get("blink_tier", 0)
            close_score = runner_up["score"] >= winner["score"] - quality.ADAPTIVE_MARGIN
            if same_tier and close_score:
                n = 2
    else:
        n = min(top_k, len(scored))

    return {
        "group_id": group_id,
        "best_photo_id": scored[0]["photo_id"],
        "candidates": [r["photo_id"] for r in scored[:n]],
        "scores": [{k: v for k, v in r.items() if k != "faces"} for r in results],
    }


def pick_best(group_id: str):
    """Compatibility helper for internal callers expecting pick_best()."""
    try:
        return best_shot_endpoint(group_id=group_id)
    except HTTPException:
        return None
