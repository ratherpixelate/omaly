"""Shared helpers for the Omaly ingestion pipeline."""
import hashlib
import os
from pathlib import Path

import pillow_heif
from PIL import Image, ImageOps

pillow_heif.register_heif_opener()  # makes Image.open() handle HEIC/HEIF

EXTS = {".jpg", ".jpeg", ".png", ".webp", ".heic", ".heif", ".tif", ".tiff", ".bmp"}
EMBED_DIM = 512  # ViT-B-32 / openai

# CPU by default: old GPUs (e.g. MX110, sm_50) are unsupported by current PyTorch.
# On a machine with a working GPU: OMALY_DEVICE=cuda uv run python -m ingestion.run_ingestion ...
DEVICE = os.environ.get("OMALY_DEVICE", "cpu")

DB_PATH = Path(__file__).resolve().parent.parent / "db" / "omaly.db"
SCHEMA_PATH = DB_PATH.parent / "schema.sql"


def photo_id(path) -> str:
    """Stable id: sha1 of the absolute filepath."""
    return hashlib.sha1(str(Path(path).resolve()).encode("utf-8")).hexdigest()


def iter_images(folder) -> list[Path]:
    folder = Path(folder).expanduser().resolve()
    if not folder.is_dir():
        raise SystemExit(f"Photo folder not found: {folder}")
    return sorted(p for p in folder.rglob("*")
                  if p.is_file() and p.suffix.lower() in EXTS and not p.name.startswith("."))


def load_rgb(path, max_side: int | None = None) -> Image.Image:
    """Open any supported image, apply EXIF rotation, return RGB (optionally downscaled)."""
    with Image.open(path) as img:
        img = ImageOps.exif_transpose(img).convert("RGB")
    if max_side:
        img.thumbnail((max_side, max_side))
    return img