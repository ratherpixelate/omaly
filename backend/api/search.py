import sqlite3
import numpy as np
from fastapi import APIRouter, HTTPException, Query
from .common import db

router = APIRouter()
_model = _tok = None
_dim = None
_ready = False
_cache = {"key": None, "ids": [], "matrix": None}


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
    if not _ready:
        warmup()
    if not _ready:
        raise HTTPException(503, "Search model not loaded (torch/open_clip missing)")
    cache = _load()
    if not cache["ids"]:
        return {"query": q, "results": []}
    scores = cache["matrix"] @ embed_text(q)
    idx = np.argsort(-scores)[:top_k]
    ids = [cache["ids"][i] for i in idx]
    with db() as c:
        rows = c.execute(
            f"SELECT id, taken_at, latitude, longitude FROM photos WHERE id IN ({','.join('?' * len(ids))})",
            ids).fetchall()
    meta = {r["id"]: r for r in rows}
    results = []
    for i in idx:
        pid = cache["ids"][i]
        r = meta[pid]
        gps = r["latitude"] is not None and r["longitude"] is not None
        results.append({
            "id": pid,
            "thumbnail_url": f"/thumbnails/{pid}.jpg",
            "taken_at": r["taken_at"] or "1970-01-01T00:00:00",
            "location": {"lat": r["latitude"], "lon": r["longitude"]} if gps else None,
            "score": round(float(scores[i]), 4),
        })
    return {"query": q, "results": results}