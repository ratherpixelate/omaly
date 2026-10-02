"""Face detection + clustering.

Backend: face_recognition (dlib). If it isn't importable, falls back to
insightface + onnxruntime automatically.

Public API:
    detect_all(photos)      -> (faces, failed)   one dict per detected face:
                               {pid, path, bbox=(x1,y1,x2,y2), emb, small, cluster}
    assign_clusters(faces)  -> counts            sets f["cluster"] ("p1".. or None=noise)
    cluster_faces(photos)   -> (assign, counts, failed)   what the DB stage uses
        assign  {photo_id: ["p1", "p3"]}
        counts  {"p1": photo_count, ...}  (ranked by size, p1 = most photos)
"""
import numpy as np
from sklearn.cluster import HDBSCAN

from . import load_rgb

MIN_CLUSTER_SIZE = 3     # a person needs >= 3 face sightings to become a cluster
MAX_SIDE = 1600          # downscale before detection (bigger = finds smaller faces, slower)
DET_SIZE = (1024, 1024)  # insightface detector input; default 640 misses small faces
DET_THRESH = 0.4         # detector confidence (default 0.5); lower = more faces found
MIN_FACE_PX = 40         # faces smaller than this are kept for debugging but not clustered

try:
    import face_recognition
except (ImportError, SystemExit):
    # face_recognition calls quit() (SystemExit) if face_recognition_models is missing
    face_recognition = None
    print("face_recognition unavailable -> falling back to insightface")

_insight = None


def backend_name() -> str:
    return "dlib (face_recognition)" if face_recognition else "insightface"


def _detect_dlib(img):
    arr = np.ascontiguousarray(np.asarray(img))
    locs = face_recognition.face_locations(arr, model="hog")  # (top, right, bottom, left)
    encs = face_recognition.face_encodings(arr, locs)
    return [{"bbox": (l, t, r, b), "emb": e} for (t, r, b, l), e in zip(locs, encs)]


def _detect_insight(img):
    global _insight
    if _insight is None:
        from insightface.app import FaceAnalysis
        _insight = FaceAnalysis(name="buffalo_l", providers=["CPUExecutionProvider"])
        _insight.prepare(ctx_id=-1, det_thresh=DET_THRESH, det_size=DET_SIZE)
    bgr = np.ascontiguousarray(np.asarray(img)[:, :, ::-1])
    return [{"bbox": tuple(float(v) for v in f.bbox), "emb": f.normed_embedding}
            for f in _insight.get(bgr)]


def detect_all(photos):
    """photos: list of (photo_id, filepath)."""
    detect = _detect_dlib if face_recognition else _detect_insight
    faces, failed = [], []
    for pid, path in photos:
        try:
            for d in detect(load_rgb(path, MAX_SIDE)):
                x1, y1, x2, y2 = d["bbox"]
                d.update(pid=pid, path=path, cluster=None,
                         small=min(x2 - x1, y2 - y1) < MIN_FACE_PX)
                faces.append(d)
        except Exception as ex:
            failed.append((path, repr(ex)))
    return faces, failed


def assign_clusters(faces) -> dict[str, int]:
    usable = [f for f in faces if not f["small"]]
    if len(usable) < MIN_CLUSTER_SIZE:
        return {}
    labels = HDBSCAN(
        min_cluster_size=MIN_CLUSTER_SIZE,
        min_samples=1,
        copy=True,
        cluster_selection_method="leaf",  # finer splits -> fewer merged people
    ).fit_predict(np.vstack([np.asarray(f["emb"], dtype="float64") for f in usable]))

    by_label: dict[int, set] = {}
    for f, lab in zip(usable, labels):
        if lab >= 0:  # -1 = noise (one-off faces), left unlabeled
            by_label.setdefault(lab, set()).add(f["pid"])
    order = sorted(by_label, key=lambda l: -len(by_label[l]))
    names = {lab: f"p{n}" for n, lab in enumerate(order, 1)}
    for f, lab in zip(usable, labels):
        f["cluster"] = names.get(lab)
    return {names[l]: len(by_label[l]) for l in order}


def cluster_faces(photos):
    faces, failed = detect_all(photos)
    counts = assign_clusters(faces)
    assign = {pid: [] for pid, _ in photos}
    for f in faces:
        if f["cluster"] and f["cluster"] not in assign[f["pid"]]:
            assign[f["pid"]].append(f["cluster"])
    for v in assign.values():
        v.sort(key=lambda c: int(c[1:]))
    return assign, counts, failed