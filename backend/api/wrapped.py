from datetime import datetime
from fastapi import APIRouter

router = APIRouter()

@router.get("/wrapped")
def wrapped():
    return {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "top_people": [{"cluster_id": "p1", "label": "Person 1", "photo_count": 12}],
        "top_locations": [{"name": "Munnar", "lat": 10.08, "lon": 77.06, "photo_count": 8}],
        "pets_detected": True,
        "best_shots": ["mock0", "mock1"],
        "narrative": "You spent the most time with Person 1 this year, with Munnar as your favourite escape.",
    }