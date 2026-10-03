import os
from pathlib import Path
import threading
import urllib.parse
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from api import search, best_shot, wrapped, thumbnails, people
from ingestion import quality


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Warm CLIP search and best-shot quality metrics in background threads
    threading.Thread(target=search.warmup, daemon=True).start()
    threading.Thread(target=quality.warm, daemon=True).start()
    yield


app = FastAPI(title="Omaly API", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

# Folder of photos to serve. Override with PHOTOS_DIR=/path/to/dir.
_demo_dir = Path(__file__).parent / "data" / "demo_photos"
_default_photos = _demo_dir if _demo_dir.is_dir() else Path.home() / "Downloads" / "photos"
PHOTOS_DIR = Path(os.environ.get("PHOTOS_DIR", _default_photos))

_IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".heic"}

app.mount(
    "/files", StaticFiles(directory=PHOTOS_DIR, check_dir=False), name="files"
)


@app.get("/health")
def health():
    return {"status": "ok"}


_VIDEO_EXTS = {".mp4", ".mov", ".mkv", ".avi", ".webm", ".m4v"}
_IMAGE_EXTS = _IMAGE_EXTS | _VIDEO_EXTS


@app.get("/photos")
def list_photos():
    if not PHOTOS_DIR.is_dir():
        return {"photos": []}

    meta_by_name = {}
    try:
        from api.common import db as get_db
        with get_db() as con:
            rows = con.execute("SELECT id, filename, burst_group_id FROM photos").fetchall()
            for r in rows:
                meta_by_name[r["filename"]] = {
                    "db_id": r["id"],
                    "burst_group_id": r["burst_group_id"],
                }
    except Exception:
        pass

    photos = []
    for f in sorted(PHOTOS_DIR.rglob("*")):
        if not f.is_file() or f.suffix.lower() not in _IMAGE_EXTS:
            continue
        rel = f.relative_to(PHOTOS_DIR)
        meta = meta_by_name.get(f.name, {})
        db_id = meta.get("db_id")
        photos.append(
            {
                "id": str(rel),
                "db_id": db_id,
                "burst_group_id": meta.get("burst_group_id"),
                "name": f.name,
                "url": "/files/" + urllib.parse.quote(str(rel)),
                "thumbnail_url": f"/thumbnails/{db_id}.jpg" if db_id else None,
                "size": f.stat().st_size,
                "modified_at": f.stat().st_mtime,
                "type": "video" if f.suffix.lower() in _VIDEO_EXTS else "photo",
                "folder": str(rel.parent) if str(rel.parent) != "." else "",
            }
        )
    return {"photos": photos}


for r in (search.router, best_shot.router, wrapped.router, thumbnails.router, people.router):
    app.include_router(r)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)

