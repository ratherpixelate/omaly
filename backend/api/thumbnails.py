import io
from fastapi import APIRouter
from fastapi.responses import Response
from PIL import Image

router = APIRouter()

@router.get("/thumbnails/{photo_id}")
def thumbnail(photo_id: str):
    # Serve a real downscaled thumbnail from the DB filepath when possible,
    # so search results show the actual photo instead of a placeholder.
    try:
        from .common import db

        with db() as c:
            row = c.execute(
                "SELECT filepath FROM photos WHERE id = ?", (photo_id,)
            ).fetchone()
        if row is not None:
            img = Image.open(row["filepath"])
            img.thumbnail((400, 400))
            if img.mode in ("RGBA", "P"):
                img = img.convert("RGB")
            buf = io.BytesIO()
            img.save(buf, "JPEG", quality=80)
            return Response(buf.getvalue(), media_type="image/jpeg")
    except Exception:
        pass
    # Fallback: deterministic solid-color placeholder (old behaviour).
    c = sum(map(ord, photo_id)) % 150
    buf = io.BytesIO()
    Image.new("RGB", (400, 300), (60 + c, 110, 170)).save(buf, "JPEG")
    return Response(buf.getvalue(), media_type="image/jpeg")