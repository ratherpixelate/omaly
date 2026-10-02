from fastapi import APIRouter, Query

router = APIRouter()

@router.get("/search")
def search(q: str = Query(..., min_length=1), top_k: int = Query(20, ge=1, le=100)):
    results = [{
        "id": f"mock{i}",
        "thumbnail_url": f"/thumbnails/mock{i}.jpg",
        "taken_at": "2026-04-12T14:33:00",
        "location": {"lat": 8.47, "lon": 76.95} if i % 2 == 0 else None,
        "score": round(0.83 - i * 0.05, 2),
    } for i in range(min(top_k, 6))]
    return {"query": q, "results": results}