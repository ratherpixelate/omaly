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
SIM_THRESHOLD = 0.93


def _timestamp(taken_at, filepath):
    if taken_at:
        try:
            return datetime.fromisoformat(taken_at).timestamp()
        except ValueError:
            pass
    try:
        return os.stat(filepath).st_mtime  # fallback when EXIF date is missing
    except OSError:
        return None


def group_bursts(rows) -> dict[str, str]:
    """rows: iterable of (id, taken_at, filepath, embedding_blob).

    Returns {photo_id: burst_group_id} only for photos in a group of 2+.
    """
    items = []
    for pid, taken_at, fp, blob in rows:
        ts = _timestamp(taken_at, fp)
        if ts is not None:
            items.append((ts, pid, np.frombuffer(blob, dtype="float32")))
    items.sort(key=lambda x: x[0])

    parent = {pid: pid for _, pid, _ in items}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for i, (ti, pi, ei) in enumerate(items):
        for tj, pj, ej in items[i + 1:]:
            if tj - ti > TIME_WINDOW_S:
                break
            if float(ei @ ej) >= SIM_THRESHOLD:
                parent[find(pj)] = find(pi)

    groups: dict[str, list[str]] = {}
    for _, pid, _ in items:
        groups.setdefault(find(pid), []).append(pid)

    return {pid: "b_" + min(members)[:8]
            for members in groups.values() if len(members) > 1
            for pid in members}