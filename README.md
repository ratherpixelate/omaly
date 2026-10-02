# Omaly: Ingestion Pipeline

Omaly is a privacy-first, fully on-device alternative to Google Photos: semantic search ("me and Arjun at the beach"), best-shot picking from bursts, and a Wrapped-style recap of people, places and pets. No photo, embedding or face ever leaves the machine.

This package is the **ingestion stage**. It turns a folder of photos into one SQLite file (`backend/db/omaly.db`) that the FastAPI backend reads and the Flutter app queries through it. Built for ASCENT'26, "Build with Local AI" track.

## What it does

```
for each photo in folder:
    read EXIF            -> taken_at, latitude, longitude
    CLIP image embedding -> 512 x float32, L2-normalized (powers semantic search)
    face detect + embed  -> cluster across ALL photos -> person ids p1, p2, ...
    object detection     -> tags such as dog, cat, bicycle
group near-duplicates    -> same burst_group_id (close in time AND visually similar)
write everything         -> SQLite
```

Every model runs locally on CPU. Weights are downloaded once on first use; after that the pipeline needs no network (set `HF_HUB_OFFLINE=1` to enforce it).

## Layout

| File | Role |
| --- | --- |
| `run_ingestion.py` | CLI. Runs stages in order: embed, faces, objects, bursts |
| `exif.py` | Date and GPS extraction (Pillow, with exifread as fallback) |
| `embeddings.py` | CLIP ViT-B-32 (OpenAI weights) image embeddings, batched |
| `faces.py` | insightface (SCRFD detector + ArcFace) and agglomerative clustering; optional dlib backend |
| `objects.py` | YOLOv8-nano object and pet tags |
| `bursts.py` | Near-duplicate grouping |
| `verify.py` | Checks the DB against the contract the backend relies on |
| `debug_faces.py` | HTML report: boxes on every face, plus crops grouped by person |
| `make_stress_folder.py` | Generates corrupt and awkward files to test robustness |

## Run it

```bash
cd backend
uv sync
uv run python -m ingestion.run_ingestion /path/to/photos --reset
uv run python -m ingestion.verify
```

Useful flags: `--stages faces objects` re-runs only those stages (they read paths from the DB), `--force` re-embeds, `--reset` rebuilds the DB from scratch. Set `OMALY_DEVICE=cuda` on a machine with a supported GPU; the default is CPU.

## Output contract

```sql
photos(id, filepath, filename, taken_at, latitude, longitude,
       embedding BLOB,        -- 512 float32, L2-normalized: np.frombuffer(blob, 'float32')
       face_cluster_ids,      -- JSON array, e.g. ["p1","p2"]
       object_tags,           -- JSON array, e.g. ["dog"]
       burst_group_id)        -- shared by near-duplicates, NULL otherwise
face_clusters(cluster_id, label, photo_count)
```

Because embeddings are unit length, cosine similarity is a plain dot product. The text side must use the same model: `ViT-B-32-quickgelu` with `pretrained="openai"`.

## Design decisions

- **One bad file never stops a batch.** Corrupt, truncated, empty and mislabeled files are skipped and reported; HEIC is supported. Tested with `make_stress_folder.py`.
- **Safe re-runs.** The embed stage upserts only the columns it owns, and commits per batch so the backend can query rows while ingestion is still running.
- **Face clustering.** Faces are merged by average distance under a threshold (`CLUSTER_DIST` in `faces.py`). Faces under 40 px are ignored because their embeddings are unreliable. People seen fewer than twice stay unlabeled.
- **Burst grouping.** Two photos are grouped if they are within 10 seconds and their CLIP similarity is at least 0.93. When a photo has no EXIF date, file time is unreliable, so a stricter similarity (0.97) is required instead. Choosing the best shot from a burst is left to the backend.
- **Inspectability.** `debug_faces.py` draws every detection, color-coded by person, so clustering quality can be checked by eye rather than trusted.

## Known limitations

- `filepath` is an absolute path on the ingesting machine; the backend remaps it when serving images.
- Person ids (`p1`, `p2`, ...) are regenerated on every run and `label` is empty in this MVP.
- GPS and dates exist only if the photos keep their EXIF. Photos forwarded through messaging apps usually lose it.
- Face and burst thresholds were tuned on a small demo set.
- The official insightface model weights are licensed for non-commercial research use.