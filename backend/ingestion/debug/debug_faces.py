"""Visual check of face detection + clustering. Writes an HTML report.

    uv run python -m ingestion.debug.debug_faces [--db path] [--out data/debug]
    xdg-open data/debug/index.html

Box colors:
    colored + pN  = assigned to cluster pN (same color = same person)
    white   "?"   = detected but unclustered (one-off / noise)
    gray   "small"= detected but below MIN_FACE_PX, ignored by clustering
A face you can SEE but that has no box at all = a detector miss.
"""
import argparse
import html
import sqlite3
import sys
from pathlib import Path

from PIL import ImageDraw, ImageFont

if __package__ is None or __package__ == "":
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))
    from ingestion import DB_PATH, load_rgb
    from ingestion.faces import MAX_SIDE, MIN_FACE_PX, assign_clusters, backend_name, detect_all
else:
    from .. import DB_PATH, load_rgb
    from ..faces import MAX_SIDE, MIN_FACE_PX, assign_clusters, backend_name, detect_all

PALETTE = [(230, 25, 75), (60, 180, 75), (0, 130, 200), (245, 130, 48), (145, 30, 180),
           (70, 240, 240), (240, 50, 230), (210, 245, 60), (0, 128, 128), (170, 110, 40),
           (128, 0, 0), (0, 0, 128)]
WHITE, GRAY = (255, 255, 255), (150, 150, 150)


def _font(size):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(DB_PATH))
    ap.add_argument("--out", default="data/debug")
    args = ap.parse_args()

    con = sqlite3.connect(args.db)
    photos = con.execute("SELECT id, filepath FROM photos ORDER BY filename").fetchall()
    print(f"{len(photos)} photos, backend: {backend_name()}")

    faces, failed = detect_all(photos)
    counts = assign_clusters(faces)

    out = Path(args.out)
    (out / "photos").mkdir(parents=True, exist_ok=True)
    (out / "crops").mkdir(exist_ok=True)

    by_photo = {}
    for f in faces:
        by_photo.setdefault(f["pid"], []).append(f)

    crops: dict[str, list[str]] = {}  # cluster id (or "noise") -> crop files
    cards = []
    for pid, path in photos:
        try:
            img = load_rgb(path, MAX_SIDE)
        except Exception as e:
            print(f"  skip {path}: {e!r}")
            continue
        clean = img.copy()
        draw = ImageDraw.Draw(img)
        lw = max(2, img.width // 300)
        font = _font(max(14, img.width // 45))
        fl = by_photo.get(pid, [])
        n_small = n_noise = n_clu = 0

        for f in fl:
            x1, y1, x2, y2 = f["bbox"]
            c = f["cluster"]
            if f["small"]:
                color, tag, n_small = GRAY, "small", n_small + 1
            elif c is None:
                color, tag, n_noise = WHITE, "?", n_noise + 1
            else:
                color, tag, n_clu = PALETTE[(int(c[1:]) - 1) % len(PALETTE)], c, n_clu + 1
            draw.rectangle([x1, y1, x2, y2], outline=color, width=lw)
            tb = draw.textbbox((0, 0), tag, font=font)
            tw, th = tb[2] - tb[0], tb[3] - tb[1]
            ty = max(0, y1 - th - 6)
            draw.rectangle([x1, ty, x1 + tw + 8, ty + th + 6], fill=color)
            draw.text((x1 + 4, ty), tag, fill=(0, 0, 0), font=font)

            if not f["small"]:  # crop from the clean copy, with 20% padding
                pad = 0.2 * max(x2 - x1, y2 - y1)
                crop = clean.crop((max(0, x1 - pad), max(0, y1 - pad),
                                   min(clean.width, x2 + pad), min(clean.height, y2 + pad)))
                crop.thumbnail((160, 160))
                key = c or "noise"
                name = f"{key}_{len(crops.get(key, []))}.jpg"
                crop.save(out / "crops" / name, quality=88)
                crops.setdefault(key, []).append(name)

        fn = f"{pid[:8]}.jpg"
        img.save(out / "photos" / fn, quality=85)
        caption = (f"{html.escape(Path(path).name)}<br>{len(fl)} detected: "
                   f"{n_clu} clustered, {n_noise} unclustered, {n_small} small")
        cards.append(f'<figure><img src="photos/{fn}" loading="lazy"><figcaption>{caption}</figcaption></figure>')
        print(f"  {Path(path).name[:50]:50s} faces={len(fl)} (clustered={n_clu}, ?={n_noise}, small={n_small})")

    sections = ["<h2>Clusters: every crop in a row should be the SAME person</h2>"]
    for cid, n_photos in counts.items():
        imgs = "".join(f'<img src="crops/{c}">' for c in crops.get(cid, []))
        sections.append(f"<h3>{cid} ({n_photos} photos, {len(crops.get(cid, []))} faces)</h3><div class=row>{imgs}</div>")
    if crops.get("noise"):
        imgs = "".join(f'<img src="crops/{c}">' for c in crops["noise"])
        sections.append(f"<h3>unclustered (&quot;?&quot;): real people here = clustering too strict</h3><div class=row>{imgs}</div>")

    page = f"""<!doctype html><meta charset=utf-8><title>Omaly face debug</title>
<style>body{{font:14px sans-serif;margin:20px;background:#111;color:#eee}}
.row img{{height:90px;margin:2px;border-radius:4px}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(420px,1fr));gap:12px}}
figure{{margin:0}}figure img{{width:100%;border-radius:6px}}figcaption{{padding:4px 0;color:#aaa}}</style>
<h1>Omaly face debug</h1>
<p>backend: {backend_name()} | min face {MIN_FACE_PX}px | colored = clustered (pN), white ? = unclustered, gray = too small.
A visible face with NO box = detector miss.</p>
{''.join(sections)}
<h2>Photos</h2><div class=grid>{''.join(cards)}</div>"""
    (out / "index.html").write_text(page, encoding="utf-8")

    total = len(faces)
    n_clu = sum(1 for f in faces if f["cluster"])
    n_small = sum(1 for f in faces if f["small"])
    print(f"\n{total} faces: {n_clu} clustered, {total - n_clu - n_small} unclustered, {n_small} small; "
          f"{len(counts)} clusters")
    for p, err in failed:
        print(f"  FAILED {p}: {err}")
    print(f"open: {out.resolve() / 'index.html'}")


if __name__ == "__main__":
    main()