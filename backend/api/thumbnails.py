import io
from fastapi import APIRouter
from fastapi.responses import Response
from PIL import Image

router = APIRouter()

@router.get("/thumbnails/{photo_id}")
def thumbnail(photo_id: str):
    c = sum(map(ord, photo_id)) % 150
    buf = io.BytesIO()
    Image.new("RGB", (400, 300), (60 + c, 110, 170)).save(buf, "JPEG")
    return Response(buf.getvalue(), media_type="image/jpeg")