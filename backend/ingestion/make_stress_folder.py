"""Create a folder of deliberately awkward files to test ingestion robustness.

    uv run python -m ingestion.make_stress_folder            # -> data/stress
    uv run python -m ingestion.run_ingestion data/stress --db data/stress.db --reset
    uv run python -m ingestion.verify --db data/stress.db

EXPECTED: run finishes without crashing; the 4 "bad_*" files are reported as
FAILED/skipped; the 5 good files land in the DB; exif_full.jpg has a date + GPS.
"""
import argparse
import random
from pathlib import Path

from PIL import Image, ImageDraw

import pillow_heif  # noqa: F401  (registers HEIC save/open)


def _img(seed, size=(640, 480)):
    rnd = random.Random(seed)
    im = Image.new("RGB", size, tuple(rnd.randint(40, 215) for _ in range(3)))
    d = ImageDraw.Draw(im)
    for _ in range(12):
        x, y = rnd.randint(0, size[0]), rnd.randint(0, size[1])
        d.ellipse([x, y, x + rnd.randint(30, 160), y + rnd.randint(30, 160)],
                  fill=tuple(rnd.randint(0, 255) for _ in range(3)))
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="data/stress")
    out = Path(ap.parse_args().out)
    out.mkdir(parents=True, exist_ok=True)

    # ---- good files ----
    exif = Image.Exif()
    exif[306] = "2025:01:15 10:30:00"          # DateTime
    exif[0x8769] = {36867: "2025:01:15 10:30:00"}  # DateTimeOriginal
    exif[0x8825] = {1: "N", 2: (8.0, 30.0, 0.0), 3: "E", 4: (76.0, 57.0, 0.0)}  # GPS ~Trivandrum
    _img(1).save(out / "exif_full.jpg", exif=exif)

    _img(2).save(out / "no_exif.png")
    _img(3).save(out / "plain.jpg")
    _img(4, (6000, 4000)).save(out / "huge_12mp.jpg", quality=80)
    try:
        _img(5).save(out / "iphone_style.heic")
    except Exception as e:
        print(f"HEIC write not available here ({e!r}); copy a real .heic in manually")

    # ---- bad files (must be skipped, not crash the batch) ----
    (out / "bad_empty.jpg").write_bytes(b"")
    (out / "bad_text_as.jpg").write_text("this is not an image")
    good = (out / "plain.jpg").read_bytes()
    (out / "bad_truncated.jpg").write_bytes(good[: len(good) // 3])
    (out / "bad_random.png").write_bytes(random.Random(9).randbytes(2048))

    print(f"wrote {len(list(out.iterdir()))} files to {out}")


if __name__ == "__main__":
    main()