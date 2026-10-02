from fastapi import APIRouter

router = APIRouter()

@router.get("/best-shot")
def best_shot_endpoint(group_id: str):
    return {"group_id": group_id, "best_photo_id": "mock0",
            "candidates": ["mock0", "mock1", "mock2"]}