"""Burst (near-duplicate) grouping.

Pseudocode:
    sort photos by timestamp (EXIF taken_at, else file mtime)
    for each pair (i, j) with t_j - t_i <= TIME_WINDOW_S:
        if cosine(emb_i, emb_j) >= SIM_THRESHOLD: union(i, j)
    every union-find set with >= 2 members is a burst
    burst id = "b_" + first 8 chars of the smallest member id  (stable across re-runs)

Embeddings are L2-normalized at ingest, so dot product == cosine similarity.
Tune SIM_THRESHOLD on your own bursts: too low merges similar-but-distinct
shots, too high splits true bursts.
"""
import os
from datetime import datetime

import numpy as np

TIME_WINDOW_S = 10.0
SIM_THRESHOLD = 0.93          # both photos have a real EXIF date
SIM_THRESHOLD_NO_EXIF = 0.97  # either photo lacks one (mtime is unreliable) -> stricter


def _timestamp(taken_at, filepath):
    """Returns (timestamp, is_exif). Falls back to file mtime when EXIF date is missing."""
    if taken_at:
        try:
            return datetime.fromisoformat(taken_at).timestamp(), True
        except ValueError:
            pass
    try:
        return os.stat(filepath).st_mtime, False
    except OSError:
        return None, False


def group_bursts(rows) -> dict[str, str]:
    """rows: iterable of (id, taken_at, filepath, embedding_blob).

    Returns {photo_id: burst_group_id} only for photos in a group of 2+.
    """
    items = []
    for pid, taken_at, fp, blob in rows:
        ts, exact = _timestamp(taken_at, fp)
        if ts is not None:
            items.append((ts, pid, np.frombuffer(blob, dtype="float32"), exact))
    items.sort(key=lambda x: x[0])

    parent = {pid: pid for _, pid, _, _ in items}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for i, (ti, pi, ei, xi) in enumerate(items):
        for tj, pj, ej, xj in items[i + 1:]:
            if tj - ti > TIME_WINDOW_S:
                break
            thr = SIM_THRESHOLD if (xi and xj) else SIM_THRESHOLD_NO_EXIF
            if float(ei @ ej) >= thr:
                parent[find(pj)] = find(pi)

    groups: dict[str, list[str]] = {}
    for _, pid, _, _ in items:
        groups.setdefault(find(pid), []).append(pid)

    return {pid: "b_" + min(members)[:8]
            for members in groups.values() if len(members) > 1
            for pid in members}