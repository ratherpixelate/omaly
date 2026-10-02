"""Verify omaly.db matches the contract the backend relies on.

    uv run python -m ingestion.verify [--db path]
Exit code 1 if any hard check fails.
"""
import argparse
import json
import sqlite3
import sys
from collections import Counter
from pathlib import Path

import numpy as np

from . import DB_PATH, EMBED_DIM


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(DB_PATH))
    args = ap.parse_args()

    con = sqlite3.connect(args.db)
    rows = con.execute(
        "SELECT id, filepath, filename, taken_at, latitude, longitude, embedding, "
        "face_cluster_ids, object_tags, burst_group_id FROM photos").fetchall()

    errors, warns = [], []
    cluster_seen = Counter()
    bursts = Counter()
    n_exif_date = n_gps = n_faces = n_tags = 0

    for pid, fp, fn, taken, lat, lon, emb, faces, tags, burst in rows:
        v = np.frombuffer(emb, dtype="float32")
        if v.shape != (EMBED_DIM,):
            errors.append(f"{fn}: embedding shape {v.shape}, expected ({EMBED_DIM},)")
        elif abs(float(np.linalg.norm(v)) - 1.0) > 1e-3:
            errors.append(f"{fn}: embedding not L2-normalized (norm={np.linalg.norm(v):.3f})")
        if not Path(fp).exists():
            warns.append(f"{fn}: file missing on this machine: {fp}")
        for name, val in (("face_cluster_ids", faces), ("object_tags", tags)):
            if val is None:
                warns.append(f"{fn}: {name} is NULL (stage not run?)")
                continue
            try:
                arr = json.loads(val)
                assert isinstance(arr, list) and all(isinstance(x, str) for x in arr)
            except Exception:
                errors.append(f"{fn}: {name} is not a JSON array of strings: {val!r}")
                continue
            if name == "face_cluster_ids":
                n_faces += bool(arr)
                cluster_seen.update(arr)
            else:
                n_tags += bool(arr)
        n_exif_date += taken is not None
        n_gps += lat is not None and lon is not None
        if burst:
            bursts[burst] += 1

    # face_clusters consistency
    fc = dict(con.execute("SELECT cluster_id, photo_count FROM face_clusters").fetchall())
    for cid, cnt in fc.items():
        if cluster_seen.get(cid, 0) != cnt:
            errors.append(f"cluster {cid}: photo_count={cnt} but {cluster_seen.get(cid, 0)} photos reference it")
    for cid in cluster_seen:
        if cid not in fc:
            errors.append(f"photos reference cluster {cid} missing from face_clusters")
    for b, cnt in bursts.items():
        if cnt < 2:
            errors.append(f"burst {b} has only {cnt} member")

    n = len(rows)
    print(f"photos: {n}")
    print(f"  with EXIF date: {n_exif_date}/{n}   with GPS: {n_gps}/{n}")
    print(f"  with faces: {n_faces}/{n}   with object tags: {n_tags}/{n}")
    print(f"face clusters: {len(fc)}  (sizes: {sorted(fc.values(), reverse=True)})")
    print(f"burst groups: {len(bursts)}  (sizes: {sorted(bursts.values(), reverse=True)})")
    for w in warns:
        print(f"WARN  {w}")
    for e in errors:
        print(f"ERROR {e}")
    print("OK" if not errors else f"FAILED: {len(errors)} error(s)")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()