import os, sqlite3
from contextlib import contextmanager
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent          # backend/
DB_PATH = Path(os.getenv("OMALY_DB", BASE / "db" / "omaly.db"))
PHOTO_DIR = Path(os.getenv("OMALY_PHOTO_DIR", BASE / "data" / "demo_photos"))
THUMB_DIR = BASE / "thumbnails"
THUMB_DIR.mkdir(exist_ok=True)

@contextmanager
def db():
    c = sqlite3.connect(DB_PATH)
    c.row_factory = sqlite3.Row
    try:
        yield c
    finally:
        c.close()

def resolve_path(fp: str):
    """Stored path if it exists here, else look for the same filename in PHOTO_DIR."""
    p = Path(fp)
    if p.exists():
        return p
    alt = PHOTO_DIR / Path(fp.replace("\\", "/")).name
    return alt if alt.exists() else None