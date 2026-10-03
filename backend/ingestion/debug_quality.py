"""Visual check of the best-shot picker. Writes an HTML report.

    uv run python -m ingestion.debug_quality [--db path] [--out data/debug]
    xdg-open data/debug/index.html

For every burst group: photos ranked best-first, boxes drawn per face,
green = open eyes / amber = half / red = closed / gray = not judged
(profile or too small). The caption carries the score breakdown, so the
ranking can be checked by eye rather than trusted -- same idea as
debug_faces.py.
"""
import argparse
import html
import sqlite3
from pathlib import Path

from PIL import ImageDraw, ImageFont

from . import DB_PATH, load_rgb
from .quality import CROP_MAX_SIDE, rank_group

GREEN, AMBER, RED, GRAY = (30, 200, 90), (245, 180, 40), (230, 60, 60), (150, 150, 150)


def _color(openness):
    if openness is None:
        return GRAY
    if openness >= 0.7:
        return GREEN
    if openness >= 0.4:
        return AMBER
    return RED


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
    groups = [g for (g,) in con.execute(
        "SELECT DISTINCT burst_group_id FROM photos WHERE burst_group_id IS NOT NULL "
        "ORDER BY burst_group_id")]
    if not groups:
        print("no burst groups in the database")
        return

    out = Path(args.out)
    (out / "photos").mkdir(parents=True, exist_ok=True)

    sections = []
    for gid in groups:
        rows = con.execute(
            "SELECT id, filepath, taken_at, face_cluster_ids FROM photos "
            "WHERE burst_group_id=? ORDER BY taken_at", (gid,)).fetchall()
        results = rank_group(con, rows)
        print(f"\n{gid} ({len(results)} photos, ranked best first):")

        cards = []
        for rank, r in enumerate(results, 1):
            mark = "\u2605 " if rank == 1 and r["score"] is not None else ""
            if r["score"] is None:
                print(f"  {rank}. {r['filename']}: FAILED {r['error']}")
                cards.append(f"<figure class=bad><figcaption>{rank}. "
                             f"{html.escape(r['filename'])} \u2014 {html.escape(str(r['error']))}"
                             f"</figcaption></figure>")
                continue
            print(f"  {rank}. {r['filename']}: score={r['score']:.3f} "
                  f"eyes={r['eyes']:.2f} sharp={r['sharpness']:.2f} "
                  f"complete={r['completeness']:.2f} conf={r['confidence']:.2f} "
                  f"closed={r['n_closed']}/{r['n_faces']}"
                  f"{' (cached)' if r['cached'] else ''}")

            path = next((fp for pid, fp, *_ in rows if pid == r["photo_id"]), None)
            try:
                img = load_rgb(path, CROP_MAX_SIDE)
            except Exception as e:
                print(f"    skip image: {e!r}")
                continue
            draw = ImageDraw.Draw(img)
            lw = max(2, img.width // 300)
            font = _font(max(14, img.width // 50))
            for f in r["faces"]:
                color = _color(f["openness"])
                x1, y1, x2, y2 = f["bbox"]
                draw.rectangle([x1, y1, x2, y2], outline=color, width=lw)
                if f["openness"] is not None:
                    tag = f"{f['openness']:.2f}"
                elif f["small"]:
                    tag = "small"
                else:
                    tag = "?"
                tb = draw.textbbox((0, 0), tag, font=font)
                tw, th = tb[2] - tb[0], tb[3] - tb[1]
                ty = max(0, y1 - th - 6)
                draw.rectangle([x1, ty, x1 + tw + 8, ty + th + 6], fill=color)
                draw.text((x1 + 4, ty + 2), tag, fill=(0, 0, 0), font=font)

            fn = f"{gid}_{rank}_{r['photo_id'][:8]}.jpg"
            img.save(out / "photos" / fn, quality=85)
            caption = (f"{mark}#{rank} {html.escape(r['filename'])}<br>"
                       f"score {r['score']:.3f} | tier {r.get('blink_tier', 0)} | "
                       f"sharp {r['sharpness']:.2f} | complete {r['completeness']:.2f}"
                       f"<br>eyes closed: {r['n_closed']}/{r['n_faces']}"
                       f"{' | cached' if r['cached'] else ''}")
            cards.append(f"<figure><img src=photos/{fn} loading=lazy>"
                         f"<figcaption>{caption}</figcaption></figure>")

        sections.append(f"<h2>{gid}</h2><div class=grid>{''.join(cards)}</div>")

    page = f"""<!doctype html><meta charset=utf-8><title>Omaly best-shot debug</title>
<style>body{{font:14px sans-serif;background:#111;color:#eee;margin:20px}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(420px,1fr));gap:12px}}
figure{{margin:0}}figure img{{width:100%;border-radius:6px}}
figure.bad{{padding:16px;background:#2a1515;border-radius:6px;color:#f99}}
figcaption{{padding:4px 0;color:#bbb}}</style>
<h1>Omaly best-shot debug</h1>
<p>Ranked best first (winner marked &#9733;). Face boxes: green = eyes open,
amber = half, red = closed, gray = not judged (profile / too small).</p>
{''.join(sections)}"""
    (out / "index.html").write_text(page, encoding="utf-8")
    print(f"\nopen: {(out / 'index.html').resolve()}")


if __name__ == "__main__":
    main()
