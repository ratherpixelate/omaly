"""Face detection + clustering.

Backend: face_recognition (dlib). If it isn't importable, falls back to
insightface + onnxruntime automatically.

cluster_faces() returns:
    assign  {photo_id: ["p1", "p3"]}   (empty list if no known faces)
    counts  {"p1": photo_count, ...}   (clusters ranked by size, p1 = biggest)
    failed  [(path, error)]
"""
import numpy as np
from sklearn.cluster import HDBSCAN

from . import load_rgb

MIN_CLUSTER_SIZE = 3   # a person needs >= 3 face sightings to become a cluster
MAX_SIDE = 1200        # downscale before detection for speed

try:
    import face_recognition
except (ImportError, SystemExit):
    # face_recognition calls quit() (SystemExit) if face_recognition_models is missing
    face_recognition = None
    print("face_recognition unavailable -> falling back to insightface")

_insight = None


def backend_name() -> str:
    return "dlib (face_recognition)" if face_recognition else "insightface"


def _encode_dlib(img):
    arr = np.ascontiguousarray(np.asarray(img))
    locs = face_recognition.face_locations(arr, model="hog")
    return face_recognition.face_encodings(arr, locs)


def _encode_insight(img):
    global _insight
    if _insight is None:
        from insightface.app import FaceAnalysis
        _insight = FaceAnalysis(name="buffalo_l", providers=["CPUExecutionProvider"])
        _insight.prepare(ctx_id=-1, det_size=(640, 640))
    bgr = np.ascontiguousarray(np.asarray(img)[:, :, ::-1])
    return [f.normed_embedding for f in _insight.get(bgr)]


def cluster_faces(photos):
    """photos: list of (photo_id, filepath)."""
    encode = _encode_dlib if face_recognition else _encode_insight
    encs, owners, failed = [], [], []
    for pid, path in photos:
        try:
            for e in encode(load_rgb(path, MAX_SIDE)):
                encs.append(np.asarray(e, dtype="float64"))
                owners.append(pid)
        except Exception as ex:
            failed.append((path, repr(ex)))

    assign = {pid: [] for pid, _ in photos}
    if len(encs) < MIN_CLUSTER_SIZE:
        return assign, {}, failed

    labels = HDBSCAN(
        min_cluster_size=MIN_CLUSTER_SIZE,
        min_samples=1,
        copy=True,
        cluster_selection_method="leaf",  # finer splits -> fewer merged people
    ).fit_predict(np.vstack(encs))

    by_label: dict[int, set] = {}
    for pid, lab in zip(owners, labels):
        if lab >= 0:  # -1 = noise (one-off faces), left unlabeled
            by_label.setdefault(lab, set()).add(pid)

    counts = {}
    for n, lab in enumerate(sorted(by_label, key=lambda l: -len(by_label[l])), 1):
        cid = f"p{n}"
        counts[cid] = len(by_label[lab])
        for pid in by_label[lab]:
            assign[pid].append(cid)
    for v in assign.values():
        v.sort(key=lambda c: int(c[1:]))
    return assign, counts, failed