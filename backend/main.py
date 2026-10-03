import os
import urllib.parse
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from api import search, best_shot, wrapped, thumbnails


@asynccontextmanager
async def lifespan(app: FastAPI):
    search.warmup()
    yield


app = FastAPI(title="Omaly API", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

# Folder of photos to serve. Override with PHOTOS_DIR=/path/to/dir.
PHOTOS_DIR = Path(
    os.environ.get(
        "PHOTOS_DIR",
        r"C:\Users\HARINANDAN B\OneDrive\Desktop\github\omaly\backend\data\demo_photos",
    )
)

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
    photos = []
    for f in sorted(PHOTOS_DIR.rglob("*")):
        if not f.is_file() or f.suffix.lower() not in _IMAGE_EXTS:
            continue
        rel = f.relative_to(PHOTOS_DIR)
        photos.append(
            {
                "id": str(rel),
                "name": f.name,
                "url": "/files/" + urllib.parse.quote(str(rel)),
                "size": f.stat().st_size,
                "modified_at": f.stat().st_mtime,
                "type": "video" if f.suffix.lower() in _VIDEO_EXTS else "photo",
                "folder": str(rel.parent) if str(rel.parent) != "." else "",
            }
        )
    return {"photos": photos}


for r in (search.router, best_shot.router, wrapped.router, thumbnails.router):
    app.include_router(r)
