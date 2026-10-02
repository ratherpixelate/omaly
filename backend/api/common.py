import os, sqlite3
from contextlib import contextmanager
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent          # backend/
DB_PATH = Path(os.getenv("OMALY_DB", BASE / "db" / "omaly.db"))

@contextmanager
def db():
    c = sqlite3.connect(DB_PATH)
    c.row_factory = sqlite3.Row
    try:
        yield c
    finally:
        c.close()