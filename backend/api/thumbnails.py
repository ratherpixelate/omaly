from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse
from PIL import Image, ImageOps
from .common import db, resolve_path, THUMB_DIR

router = APIRouter()

@router.get("/thumbnails/{photo_id}")
def thumbnail(photo_id: str):
    photo_id = photo_id.removesuffix(".jpg")
    out = THUMB_DIR / f"{photo_id}.jpg"
    if not out.exists():
        with db() as c:
            row = c.execute("SELECT filepath FROM photos WHERE id=?", (photo_id,)).fetchone()
        if not row:
            raise HTTPException(404, "photo not found")
        src = resolve_path(row["filepath"])
        if src is None:
            raise HTTPException(404, f"image file not found for {row['filepath']}")
        img = ImageOps.exif_transpose(Image.open(src)).convert("RGB")
        img.thumbnail((400, 400))
        img.save(out, "JPEG", quality=80)
    return FileResponse(out, media_type="image/jpeg",
                        headers={"Cache-Control": "public, max-age=86400"})
