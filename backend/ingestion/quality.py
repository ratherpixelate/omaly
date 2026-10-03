"""Burst best-shot scoring: rank a burst group and pick its top 1-2 photos.

Everything comes from ONE insightface pass per photo (detection + 68-pt
landmarks). The ArcFace recognition model is deliberately NOT loaded: it
costs ~2.3s/photo measured, and matching faces across near-duplicate burst
frames by bbox position is enough here.

Scoring, per photo:
* eyes      Eye Aspect Ratio on the two 6-pt eye rings, judged PERSON-relative:
            faces are matched across the burst (greedy mutual-nearest bbox
            centres) and each eye is compared to that person's widest opening
            anywhere in the group. A blink sinks the photo; a naturally
            narrow-eyed person is not punished in every frame.
* sharpness Laplacian variance (pure numpy) on a fixed-scale grayscale copy and
            on per-face crops, min-max normalized INSIDE the burst --
            near-duplicates share a scene, so relative beats any absolute
            threshold.
* complete  faces detected vs people the faces stage found (face_cluster_ids);
            catches someone out of frame or blurred past detection.
* confidence mean detector confidence.

    score = 0.45*eyes + 0.35*sharp + 0.10*complete + 0.10*confidence

Raw per-photo facts are cached in the photo_quality table keyed by file mtime.
The group-dependent part (tracks, ear maxima, normalization) is cheap and
recomputed per request -- it is what makes sharpness relative to the burst.

Debug it visually:  uv run python -m ingestion.debug.debug_quality
"""
import json
import math
import os
import sqlite3
import threading
from datetime import datetime

import numpy as np
from PIL import Image

from . import DB_PATH, load_rgb

# --- constants --------------------------------------------------------------------------
MAX_SIDE = 1024            # detection runs here; EAR is a ratio so scale doesn't matter
CROP_MAX_SIDE = 2048       # sharpness is measured on this larger copy (blur dies in downsampling)
DET_SIZE = (1024, 1024)    # insightface detector input, same as faces.py
DET_THRESH = 0.4           # same as faces.py
MIN_FACE_PX = 40           # same as faces.py: landmarks below this are noise
FACE_CROP_PX = 128         # every face crop resamples here before the Laplacian

EAR_MAX = 0.60             # geometrically impossible above -> degenerate ring, drop it
EAR_HARD = 0.15            # at/below this an eye is closed, full stop
EAR_REF_FLOOR = 0.25        # never divide by a person's max below this (single-sighting faces)
YAW_GATE = 0.40            # |nose - eye midpoint| / interocular; past this EAR foreshortens
MATCH_GATE = 0.12          # face centres may travel at most this fraction of the image diagonal
CLOSED_FACE_AT = 0.50      # faces below this openness are reported as closed (reporting only)

W_EYES, W_SHARP, W_COMPLETE, W_CONF = 0.45, 0.35, 0.10, 0.10
FACE_SHARP_SHARE = 0.60    # of the sharpness term, face crops vs whole frame
NEUTRAL = 0.5              # score when a signal is unavailable (no usable eyes / flat group)
ADAPTIVE_MARGIN = 0.05     # runner-up joins the winner only within this distance of its score

_analyzer = None
_analyzer_lock = threading.RLock()


# --- analyzer ---------------------------------------------------------------------------
def _get_analyzer():
    """Lazy singleton: SCRFD detection + 68-pt 3D landmarks (no recognition model)."""
    global _analyzer
    if _analyzer is None:
        with _analyzer_lock:
            if _analyzer is None:
                from insightface.app import FaceAnalysis
                _analyzer = FaceAnalysis(name="buffalo_l", providers=["CPUExecutionProvider"],
                                         allowed_modules=["detection", "landmark_3d_68"])
                _analyzer.prepare(ctx_id=-1, det_thresh=DET_THRESH, det_size=DET_SIZE)
    return _analyzer


def warm():
    """Background startup work: load models, then pre-compute metrics for burst
    photos so the first /best-shot is instant. Best-effort; failures are logged
    and ignored."""
    try:
        _get_analyzer()
        con = sqlite3.connect(DB_PATH)
        try:
            ensure_table(con)
            rows = con.execute(
                "SELECT id, filepath FROM photos WHERE burst_group_id IS NOT NULL").fetchall()
            for pid, fp in rows:
                try:
                    mtime = os.stat(fp).st_mtime
                except OSError:
                    continue
                row = con.execute("SELECT mtime FROM photo_quality WHERE photo_id=?",
                                  (pid,)).fetchone()
                if not row or row[0] != mtime:
                    get_metrics(con, pid, fp)
        finally:
            con.close()
        print("[quality] warm-up done: burst metrics cached")
    except Exception as ex:
        print(f"[quality] warm-up skipped: {ex!r}")


# --- metric primitives ------------------------------------------------------------------
def _ear(ring) -> float | None:
    """Eye Aspect Ratio from a 6-pt iBUG eye ring; None if degenerate/unphysical."""
    d = lambda i, j: math.hypot(float(ring[i][0] - ring[j][0]), float(ring[i][1] - ring[j][1]))
    width = d(0, 3)
    if width <= 1e-6:
        return None
    v = (d(1, 5) + d(2, 4)) / (2.0 * width)
    if not (0.0 < v <= EAR_MAX):
        return None
    return v


def _yaw_ok(lm) -> bool:
    """Rough frontal check: nose tip should sit near the eye midpoint."""
    e_l = lm[36:42].mean(axis=0)
    e_r = lm[42:48].mean(axis=0)
    interocular = math.hypot(float(e_r[0] - e_l[0]), float(e_r[1] - e_l[1]))
    if interocular < 1e-6:
        return False
    nose = lm[30]  # iBUG nose tip
    return bool(abs(float(nose[0]) - float(e_l[0] + e_r[0]) / 2) / interocular <= YAW_GATE)


def _lap_var(arr) -> float:
    """Variance of the 4-neighbour Laplacian: the classic blur measure."""
    lap = (-4.0 * arr[1:-1, 1:-1] + arr[:-2, 1:-1] + arr[2:, 1:-1]
           + arr[1:-1, :-2] + arr[1:-1, 2:])
    return float(lap.var())


def _square_crop(gray, x1, y1, x2, y2):
    h, w = gray.shape
    x1, y1 = max(0, int(x1)), max(0, int(y1))
    x2, y2 = min(w, int(x2) + 1), min(h, int(y2) + 1)
    crop = gray[y1:y2, x1:x2]
    if crop.shape[0] < 8 or crop.shape[1] < 8:
        return None
    if crop.shape != (FACE_CROP_PX, FACE_CROP_PX):
        im = Image.fromarray(np.clip(crop, 0, 255).astype(np.uint8))
        im = im.resize((FACE_CROP_PX, FACE_CROP_PX), Image.Resampling.BILINEAR)
        crop = np.asarray(im, dtype=np.float64)
    return crop


def analyze_photo(path):
    """One insightface pass -> raw per-photo facts (JSON-safe). Never raises:
    unreadable files come back as {"error": ...}."""
    try:
        img = load_rgb(path, CROP_MAX_SIDE)
        gray = np.asarray(img.convert("L"), dtype=np.float64)
        det = img.copy()
        if max(det.size) > MAX_SIDE:
            det.thumbnail((MAX_SIDE, MAX_SIDE))
        scale = img.width / det.width
        bgr = np.ascontiguousarray(np.asarray(det)[:, :, ::-1])
        analyzer = _get_analyzer()
        with _analyzer_lock:
            faces = analyzer.get(bgr)

        out_faces = []
        for f in faces:
            bbox = [float(v) for v in f.get("bbox")]
            w_det = bbox[2] - bbox[0]
            h_det = bbox[3] - bbox[1]
            small = bool(min(w_det, h_det) < MIN_FACE_PX)
            lm = f.get("landmark_3d_68")
            if lm is None or small:
                ears, yaw = [None, None], False
            else:
                lm = np.asarray(lm, dtype=np.float64)[:, :2]
                ears = [_ear(lm[36:42]), _ear(lm[42:48])]
                yaw = bool(_yaw_ok(lm))
            full = [round(bbox[0] * scale, 1), round(bbox[1] * scale, 1),
                    round(bbox[2] * scale, 1), round(bbox[3] * scale, 1)]
            face_sharp = None
            if not small:
                crop = _square_crop(gray, *full)
                if crop is not None:
                    face_sharp = round(_lap_var(crop), 3)
            out_faces.append({
                "bbox": full,
                "det": round(float(f.get("det_score", 0.0)), 4),
                "small": small,
                "ears": [None if e is None else round(e, 4) for e in ears],
                "yaw_ok": yaw,
                "face_sharp": face_sharp,
            })
        return {"v": 1, "size": [img.width, img.height],
                "global_sharp": round(_lap_var(gray), 3), "faces": out_faces}
    except Exception as ex:
        return {"error": repr(ex)}


# --- cache ------------------------------------------------------------------------------
def ensure_table(con):
    con.execute("""
        CREATE TABLE IF NOT EXISTS photo_quality (
            photo_id TEXT PRIMARY KEY,   -- photos.id
            mtime REAL NOT NULL,         -- file mtime when computed (invalidation key)
            metrics TEXT NOT NULL,       -- JSON: raw per-photo facts, see analyze_photo()
            computed_at TEXT NOT NULL
        )""")
    con.commit()


def get_metrics(con, photo_id, path) -> tuple[dict, bool]:
    """Read-through cache: (facts, was_cached). Analyzes + stores on miss."""
    try:
        mtime = os.stat(path).st_mtime
    except OSError as ex:
        return {"error": f"file not readable: {ex}"}, False
    row = con.execute("SELECT mtime, metrics FROM photo_quality WHERE photo_id=?",
                      (photo_id,)).fetchone()
    if row and row[0] == mtime:
        try:
            facts = json.loads(row[1])
            if "error" not in facts:
                return facts, True
        except (TypeError, ValueError):
            pass
    facts = analyze_photo(path)
    if "error" not in facts:
        con.execute(
            "INSERT INTO photo_quality (photo_id, mtime, metrics, computed_at) VALUES (?,?,?,?) "
            "ON CONFLICT(photo_id) DO UPDATE SET mtime=excluded.mtime, "
            "metrics=excluded.metrics, computed_at=excluded.computed_at",
            (photo_id, mtime, json.dumps(facts), datetime.now().isoformat(timespec="seconds")))
        con.commit()
    return facts, False


# --- group scoring ----------------------------------------------------------------------
def _center(bbox):
    return ((bbox[0] + bbox[2]) / 2, (bbox[1] + bbox[3]) / 2)


def _build_tracks(members) -> list[list]:
    """Match faces across the burst's near-duplicate frames (greedy mutual-nearest
    centres, gated) and judge each face against its track's widest EAR.
    Returns per-member lists of face openness (None = not judged)."""
    parent = []

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb

    offsets = []
    for m in members:
        offsets.append(len(parent))
        parent.extend(range(len(parent), len(parent) + len(m["facts"]["faces"])))

    centers = [[_center(f["bbox"]) for f in m["facts"]["faces"]] for m in members]
    diags = [math.hypot(*m["facts"].get("size", [0, 0])) for m in members]

    for i in range(len(members)):
        for j in range(i + 1, len(members)):
            gate = MATCH_GATE * min(diags[i], diags[j])
            if gate <= 0 or not centers[i] or not centers[j]:
                continue
            free_i, free_j = set(range(len(centers[i]))), set(range(len(centers[j])))
            dists = sorted(
                (math.hypot(a[0] - b[0], a[1] - b[1]), ai, bj)
                for ai, a in enumerate(centers[i])
                for bj, b in enumerate(centers[j]))
            for d, ai, bj in dists:
                if d > gate:
                    break
                if ai in free_i and bj in free_j:
                    union(offsets[i] + ai, offsets[j] + bj)
                    free_i.discard(ai)
                    free_j.discard(bj)

    # widest trustworthy EAR per (track, eye ring)
    ring_max: dict[tuple, float] = {}
    flat = [(offsets[i] + k, f) for i, m in enumerate(members)
            for k, f in enumerate(m["facts"]["faces"])]
    for idx, f in flat:
        if not f["yaw_ok"]:
            continue
        for r, e in enumerate(f["ears"]):
            if e is not None:
                key = (find(idx), r)
                ring_max[key] = max(ring_max.get(key, 0.0), e)

    # per-face openness: 0 for a blink, 1 at the person's own widest
    opens: list[list] = [[] for _ in members]
    for i, m in enumerate(members):
        for k, f in enumerate(m["facts"]["faces"]):
            per_eye = []
            if f["yaw_ok"]:
                for r, e in enumerate(f["ears"]):
                    if e is None:
                        continue
                    ref = max(ring_max.get((find(offsets[i] + k), r), 0.0), EAR_REF_FLOOR)
                    per_eye.append(0.0 if e <= EAR_HARD else min(1.0, e / ref))
            opens[i].append(sum(per_eye) / len(per_eye) if per_eye else None)
    return opens


def _minmax(vals) -> list[float]:
    lo, hi = min(vals), max(vals)
    if hi - lo < 1e-9:
        return [NEUTRAL] * len(vals)
    return [(v - lo) / (hi - lo) for v in vals]


def rank_group(con, rows) -> list[dict]:
    """rows: (id, filepath, taken_at, face_cluster_ids) for one burst group.
    Returns results sorted best-first; unreadable photos last with score=None."""
    ensure_table(con)

    members = []
    for pid, fp, taken, fc in rows:
        try:
            expected = len(json.loads(fc)) if fc else None
        except (TypeError, ValueError):
            expected = None
        facts, cached = get_metrics(con, pid, fp)
        members.append({"id": pid, "path": fp, "taken": taken,
                        "expected": expected, "facts": facts, "cached": cached})

    ok = [i for i, m in enumerate(members) if "error" not in m["facts"]]
    opens = _build_tracks([members[i] for i in ok]) if ok else []

    raw = {}
    for n, i in enumerate(ok):
        m, faces, face_opens = members[i], members[i]["facts"]["faces"], opens[n]
        num = den = 0.0
        n_closed = 0
        f_sharp = []
        for f, o in zip(faces, face_opens):
            x1, y1, x2, y2 = f["bbox"]
            area = max(1.0, (x2 - x1) * (y2 - y1))
            if o is not None:
                w = math.sqrt(area)
                num += w * o
                den += w
                n_closed += o < CLOSED_FACE_AT
            if f["face_sharp"] is not None:
                f_sharp.append((math.log1p(f["face_sharp"]), area))
        expected = members[i]["expected"]
        dets = [f["det"] for f in faces] or [0.0]
        raw[i] = {
            "eyes": num / den if den else NEUTRAL,
            "n_closed": n_closed,
            "n_faces": len(faces),
            "g": math.log1p(m["facts"]["global_sharp"]),
            "f": (sum(v * a for v, a in f_sharp) / sum(a for _, a in f_sharp)
                  if f_sharp else None),
            "complete": min(1.0, len(faces) / expected) if expected else 1.0,
            "conf": min(1.0, max(0.0, (sum(dets) / len(dets) - DET_THRESH) / (1 - DET_THRESH))),
        }

    g_norm = dict(zip(ok, _minmax([raw[i]["g"] for i in ok]))) if ok else {}
    with_f = [i for i in ok if raw[i]["f"] is not None]
    f_norm = dict(zip(with_f, _minmax([raw[i]["f"] for i in with_f]))) if with_f else {}

    has_faces = any(raw[i]["n_faces"] > 0 for i in ok) if ok else False
    max_faces = max((raw[i]["n_faces"] for i in ok), default=0) if ok else 0

    results = []
    for i in ok:
        m, r = members[i], raw[i]
        sharp = (FACE_SHARP_SHARE * f_norm[i] + (1 - FACE_SHARP_SHARE) * g_norm[i]
                 if i in f_norm else g_norm[i])
        if has_faces:
            missing_faces = max(0, max_faces - r["n_faces"])
            blink_tier = r["n_closed"] + missing_faces
            base_quality = 0.50 * sharp + 0.35 * r["eyes"] + 0.15 * r["complete"]
            score = max(0.0, base_quality - 0.25 * blink_tier)
        else:
            blink_tier = 0
            score = sharp

        results.append({
            "photo_id": m["id"],
            "filename": os.path.basename(m["path"]),
            "taken_at": m["taken"],
            "score": round(score, 4),
            "blink_tier": blink_tier,
            "eyes": round(r["eyes"], 4),
            "sharpness": round(sharp, 4),
            "completeness": round(r["complete"], 4),
            "confidence": round(r["conf"], 4),
            "n_faces": r["n_faces"],
            "n_closed": r["n_closed"],
            "cached": m["cached"],
            "error": None,
            # annotated faces: for debug_quality.py, stripped from the API response
            "faces": [{**f, "openness": o}
                      for f, o in zip(m["facts"]["faces"], opens[ok.index(i)])],
        })
    for i, m in enumerate(members):
        if i not in raw:
            results.append({
                "photo_id": m["id"], "filename": os.path.basename(m["path"]),
                "taken_at": m["taken"], "score": None, "blink_tier": 999,
                "eyes": None, "sharpness": None,
                "completeness": None, "confidence": None, "n_faces": 0, "n_closed": 0,
                "cached": m["cached"], "error": m["facts"]["error"], "faces": [],
            })

    if has_faces:
        results.sort(key=lambda r: (r["score"] is None,
                                    r["blink_tier"],
                                    -(r["score"] or 0.0), -(r["sharpness"] or 0.0),
                                    r["taken_at"] or "9999"))
    else:
        results.sort(key=lambda r: (r["score"] is None,
                                    -(r["score"] or 0.0), -(r["sharpness"] or 0.0),
                                    r["taken_at"] or "9999"))
    return results
