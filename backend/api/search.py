import json
import re
import sqlite3
import urllib.parse
import numpy as np
from fastapi import APIRouter, HTTPException, Query
from .common import db

router = APIRouter()
_model = _tok = None
_dim = None
_ready = False
_cache = {"key": None, "ids": [], "matrix": None}

GENERIC_FACE_TERMS = {
    "person", "persons", "people", "face", "faces", "someone", "human",
    "humans", "portrait", "portraits", "selfie", "selfies", "everybody",
    "everyone", "somebody",
}


def warmup():
    """Load the CLIP model. Safe to call without torch installed: the server
    still boots and /search answers 503 until the model is available."""
    global _model, _tok, _dim, _ready
    try:
        import torch
        import open_clip
    except ImportError:
        print("[omaly] torch/open_clip not installed; /search disabled")
        return
    _model, _, _ = open_clip.create_model_and_transforms("ViT-B-32", pretrained="openai")
    _model.eval()
    _tok = open_clip.get_tokenizer("ViT-B-32")
    _dim = embed_text("warmup").shape[0]
    _ready = True
    print(f"[omaly] CLIP ready, text embedding dim = {_dim}")


def embed_text(q: str) -> np.ndarray:
    import torch

    with torch.no_grad():
        t = _model.encode_text(_tok([q]))
        t = t / t.norm(dim=-1, keepdim=True)
    return t[0].numpy().astype("float32")


def _load():
    """Reloads whenever ingestion adds rows, so partial data works."""
    try:
        with db() as c:
            key = tuple(c.execute("SELECT COUNT(*), COALESCE(MAX(rowid),0) FROM photos").fetchone())
            if key == _cache["key"]:
                return _cache
            rows = c.execute("SELECT id, embedding FROM photos").fetchall()
    except sqlite3.OperationalError:
        return {"ids": [], "matrix": None}   # table not created yet
    ids, vecs = [], []
    for r in rows:
        v = np.frombuffer(r["embedding"], dtype="float32")
        if v.shape[0] != _dim:
            raise HTTPException(500, f"Embedding dim mismatch: photo {r['id']} has {v.shape[0]}, text model gives {_dim}")
        ids.append(r["id"]); vecs.append(v)
    m = np.vstack(vecs) if vecs else np.zeros((0, _dim), "float32")
    m = m / np.clip(np.linalg.norm(m, axis=1, keepdims=True), 1e-9, None)
    _cache.update(key=key, ids=ids, matrix=m)
    return _cache


@router.get("/search")
def search(q: str = Query(..., min_length=1), top_k: int = Query(20, ge=1, le=100)):
    k = int(top_k.default if hasattr(top_k, "default") else top_k)
    q_clean = q.strip().lower()
    results = []
    seen_ids = set()

    # 1. Match people / faces by name, renamed label, cluster ID, number, or generic terms
    matched_cids = set()
    cluster_meta = {}
    is_generic_face_query = q_clean in GENERIC_FACE_TERMS

    try:
        with db() as c:
            clusters = c.execute("SELECT cluster_id, label, photo_count FROM face_clusters").fetchall()
            cluster_aliases = {}
            for r in clusters:
                cid = r["cluster_id"]
                label = (r["label"] or "").strip()
                num_str = cid.replace("p", "").strip()
                default_name = f"Person {num_str}" if num_str.isdigit() else f"Person {cid}"
                display_name = label if label else default_name
                cluster_meta[cid] = display_name

                aliases = set()
                aliases.add(cid.lower())
                aliases.add(f"p {num_str}".lower())
                aliases.add(default_name.lower())
                aliases.add(f"person{num_str}".lower())
                if num_str.isdigit():
                    aliases.add(num_str)
                    if int(num_str) < 10:
                        aliases.add(f"0{num_str}")
                        aliases.add(f"person 0{num_str}".lower())
                        aliases.add(f"person0{num_str}".lower())
                if label:
                    aliases.add(label.lower())
                    for part in label.lower().split():
                        if len(part) >= 2:
                            aliases.add(part)

                cluster_aliases[cid] = {
                    "label": label.lower() if label else None,
                    "aliases": aliases,
                    "display_name": display_name,
                }

            if is_generic_face_query:
                # Match all clusters that have at least one photo
                matched_cids = {r["cluster_id"] for r in clusters if (r["photo_count"] or 0) > 0}
            else:
                # Exact or alias match on full query
                for cid, info in cluster_aliases.items():
                    if q_clean in info["aliases"]:
                        matched_cids.add(cid)
                        continue
                    lbl = info["label"]
                    if lbl:
                        if (len(q_clean) >= 2 and lbl.startswith(q_clean)) or (len(q_clean) >= 3 and q_clean in lbl):
                            matched_cids.add(cid)
                            continue

                # Token-level match for multi-word queries (e.g. "Chris and Joseph" or "Chris Joseph")
                tokens = [t for t in re.split(r"[\s,;&+/]+", q_clean) if t and t not in ("and", "with", "or", "&")]
                if len(tokens) > 1:
                    for t in tokens:
                        for cid, info in cluster_aliases.items():
                            if t in info["aliases"]:
                                matched_cids.add(cid)
                            elif info["label"] and (len(t) >= 2 and info["label"].startswith(t)):
                                matched_cids.add(cid)

            if matched_cids:
                rows = c.execute(
                    "SELECT id, filename, burst_group_id, taken_at, latitude, longitude, face_cluster_ids FROM photos "
                    "WHERE face_cluster_ids IS NOT NULL AND face_cluster_ids != '[]' "
                    "ORDER BY taken_at DESC, id ASC"
                ).fetchall()

                for r in rows:
                    raw_fc = r["face_cluster_ids"]
                    try:
                        p_cids = set(json.loads(raw_fc or "[]"))
                    except Exception:
                        p_cids = set()

                    hit = p_cids & matched_cids
                    if not hit:
                        continue

                    pid = r["id"]
                    if pid in seen_ids:
                        continue
                    seen_ids.add(pid)

                    # Determine appropriate badge
                    if is_generic_face_query or len(matched_cids) > 1:
                        sorted_hits = sorted(hit, key=lambda x: int(x[1:]) if x[1:].isdigit() else 999)
                        names = [cluster_meta[c] for c in sorted_hits if c in cluster_meta]
                        badge = ", ".join(names[:3]) + ("..." if len(names) > 3 else "")
                    else:
                        target_cid = next(iter(matched_cids))
                        badge = cluster_meta.get(target_cid, "Person")

                    gps = r["latitude"] is not None and r["longitude"] is not None
                    fname = r["filename"]
                    results.append({
                        "id": pid,
                        "filename": fname,
                        "url": f"/files/{urllib.parse.quote(fname)}" if fname else None,
                        "burst_group_id": r["burst_group_id"],
                        "thumbnail_url": f"/thumbnails/{pid}.jpg",
                        "taken_at": r["taken_at"] or "1970-01-01T00:00:00",
                        "location": {"lat": r["latitude"], "lon": r["longitude"]} if gps else None,
                        "score": 1.0,
                        "matched_person": badge,
                    })
    except Exception as e:
        print(f"[omaly search] Person search error: {e}")

    # If the user searched for a person/face, ONLY return photos featuring that person!
    if matched_cids or is_generic_face_query:
        return {"query": q, "results": results[:k]}

    # 2. Match photo filenames (e.g. "IMG_0951", "0951")
    matched_filenames = False
    if len(q_clean) >= 2:
        try:
            with db() as c:
                fname_rows = c.execute(
                    "SELECT id, filename, burst_group_id, taken_at, latitude, longitude FROM photos "
                    "WHERE LOWER(filename) LIKE ? ORDER BY taken_at DESC, id ASC",
                    (f"%{q_clean}%",),
                ).fetchall()
                if fname_rows:
                    matched_filenames = True
                for r in fname_rows:
                    pid = r["id"]
                    if pid not in seen_ids:
                        seen_ids.add(pid)
                        gps = r["latitude"] is not None and r["longitude"] is not None
                        fname = r["filename"]
                        results.append({
                            "id": pid,
                            "filename": fname,
                            "url": f"/files/{urllib.parse.quote(fname)}" if fname else None,
                            "burst_group_id": r["burst_group_id"],
                            "thumbnail_url": f"/thumbnails/{pid}.jpg",
                            "taken_at": r["taken_at"] or "1970-01-01T00:00:00",
                            "location": {"lat": r["latitude"], "lon": r["longitude"]} if gps else None,
                            "score": 0.98,
                        })
        except Exception as e:
            print(f"[omaly search] Filename search error: {e}")

    if matched_filenames:
        return {"query": q, "results": results[:k]}

    # 3. Semantic CLIP search for scenes, objects, and visual concepts
    if len(results) < k:
        if not _ready:
            warmup()
        if _ready:
            cache = _load()
            if cache["ids"] and cache["matrix"] is not None:
                scores = cache["matrix"] @ embed_text(q)
                idx = np.argsort(-scores)
                needed_ids = []
                score_map = {}
                for i in idx:
                    pid = cache["ids"][i]
                    if pid not in seen_ids:
                        needed_ids.append(pid)
                        score_map[pid] = round(float(scores[i]), 4)
                        if len(results) + len(needed_ids) >= k:
                            break
                if needed_ids:
                    with db() as c:
                        rows = c.execute(
                            f"SELECT id, filename, burst_group_id, taken_at, latitude, longitude FROM photos WHERE id IN ({','.join('?' * len(needed_ids))})",
                            needed_ids,
                        ).fetchall()
                    meta = {r["id"]: r for r in rows}
                    for pid in needed_ids:
                        if pid in meta:
                            r = meta[pid]
                            gps = r["latitude"] is not None and r["longitude"] is not None
                            fname = r["filename"]
                            results.append({
                                "id": pid,
                                "filename": fname,
                                "url": f"/files/{urllib.parse.quote(fname)}" if fname else None,
                                "burst_group_id": r["burst_group_id"],
                                "thumbnail_url": f"/thumbnails/{pid}.jpg",
                                "taken_at": r["taken_at"] or "1970-01-01T00:00:00",
                                "location": {"lat": r["latitude"], "lon": r["longitude"]} if gps else None,
                                "score": score_map[pid],
                            })
        elif not results:
            raise HTTPException(503, "Search model not loaded (torch/open_clip missing)")

    return {"query": q, "results": results[:k]}