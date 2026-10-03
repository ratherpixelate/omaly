"""Omaly ingestion runner.

Run from the backend/ directory:
    uv run python -m ingestion.run_ingestion /path/to/photos
    uv run python -m ingestion.run_ingestion /path/to/photos --reset      # fresh DB (final demo run)
    uv run python -m ingestion.run_ingestion --stages faces objects       # re-run later stages only
    uv run python -m ingestion.run_ingestion --stages bursts

Stages (always executed in this order): embed -> faces -> objects -> bursts
Only `embed` needs the folder; later stages read filepaths from the DB.
"""
import argparse
import json
import sqlite3
import sys

from . import DB_PATH, EMBED_DIM, SCHEMA_PATH, iter_images, photo_id

STAGE_ORDER = ["embed", "faces", "objects", "bursts"]

UPSERT = """
INSERT INTO photos (id, filepath, filename, taken_at, latitude, longitude, embedding)
VALUES (?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
    filepath=excluded.filepath, filename=excluded.filename,
    taken_at=excluded.taken_at, latitude=excluded.latitude,
    longitude=excluded.longitude, embedding=excluded.embedding
"""  # only touches columns owned by this stage; later-stage columns survive re-runs


def stage_embed(con, folder, force):
    from .embeddings import embed_files
    from .exif import extract_exif

    files = iter_images(folder)
    if not files:
        sys.exit(f"No supported images found in {folder}")
    done = {r[0] for r in con.execute("SELECT id FROM photos")}
    todo = [p for p in files if force or photo_id(p) not in done]
    print(f"[embed] {len(files)} images found, {len(todo)} to process")

    ok, failed = 0, []
    for results in embed_files(todo):
        rows = []
        for p, emb, err in results:
            if emb is None:
                failed.append((p, err))
                print(f"  SKIP {p.name}: {err}")
                continue
            taken, lat, lon = extract_exif(p)
            assert emb.dtype.name == "float32" and emb.shape == (EMBED_DIM,)
            rows.append((photo_id(p), str(p.resolve()), p.name, taken, lat, lon,
                         emb.astype("float32").tobytes()))
        con.executemany(UPSERT, rows)
        con.commit()  # commit per batch so the backend sees rows immediately
        ok += len(rows)
        print(f"  {ok}/{len(todo)} written")
    return failed


def stage_faces(con):
    from .faces import backend_name, cluster_faces

    photos = con.execute("SELECT id, filepath FROM photos").fetchall()
    if not photos:
        print("[faces] no photos in DB, skipping")
        return []
    print(f"[faces] {len(photos)} photos, backend: {backend_name()}")
    assign, counts, failed = cluster_faces(photos)
    with con:
        con.executemany("UPDATE photos SET face_cluster_ids=? WHERE id=?",
                        [(json.dumps(ids), pid) for pid, ids in assign.items()])
        con.execute("DELETE FROM face_clusters")  # clustering is global: rebuild
        con.executemany("INSERT INTO face_clusters (cluster_id, label, photo_count) VALUES (?, NULL, ?)",
                        list(counts.items()))
    print(f"  {len(counts)} clusters: {counts}")
    return failed


def stage_objects(con):
    from .objects import tag_image

    photos = con.execute("SELECT id, filepath FROM photos").fetchall()
    if not photos:
        print("[objects] no photos in DB, skipping")
        return []
    print(f"[objects] {len(photos)} photos")
    failed = []
    for n, (pid, fp) in enumerate(photos, 1):
        try:
            con.execute("UPDATE photos SET object_tags=? WHERE id=?",
                        (json.dumps(tag_image(fp)), pid))
        except Exception as e:
            failed.append((fp, repr(e)))
        if n % 20 == 0:
            con.commit()
    con.commit()
    return failed


def stage_bursts(con):
    from .bursts import group_bursts

    rows = con.execute("SELECT id, taken_at, filepath, embedding FROM photos").fetchall()
    groups = group_bursts(rows)
    with con:
        con.execute("UPDATE photos SET burst_group_id=NULL")
        con.executemany("UPDATE photos SET burst_group_id=? WHERE id=?",
                        [(gid, pid) for pid, gid in groups.items()])
    print(f"[bursts] {len(set(groups.values()))} groups covering {len(groups)} photos")
    return []


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("folder", nargs="?", help="photo folder (needed for the embed stage)")
    ap.add_argument("--db", default=str(DB_PATH))
    ap.add_argument("--stages", nargs="+", choices=STAGE_ORDER, default=STAGE_ORDER)
    ap.add_argument("--force", action="store_true", help="re-embed already ingested photos")
    ap.add_argument("--reset", action="store_true", help="delete the DB first (use for the final demo run)")
    args = ap.parse_args()

    if "embed" in args.stages and not args.folder:
        sys.exit("folder is required for the embed stage")

    if args.reset:
        from pathlib import Path
        Path(args.db).unlink(missing_ok=True)

    con = sqlite3.connect(args.db)
    con.executescript(SCHEMA_PATH.read_text())

    all_failed = []
    for stage in STAGE_ORDER:
        if stage not in args.stages:
            continue
        if stage == "embed":
            all_failed += stage_embed(con, args.folder, args.force)
        else:
            all_failed += {"faces": stage_faces, "objects": stage_objects, "bursts": stage_bursts}[stage](con)

    n = con.execute("SELECT COUNT(*) FROM photos").fetchone()[0]
    print(f"\ndone: {n} photos in {args.db}, {len(all_failed)} failures")
    for p, err in all_failed:
        print(f"  FAILED {p}: {err}")
    con.close()


if __name__ == "__main__":
    main()