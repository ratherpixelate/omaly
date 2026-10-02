CREATE TABLE IF NOT EXISTS photos (
    id TEXT PRIMARY KEY,            -- sha1 of absolute filepath
    filepath TEXT NOT NULL,         -- absolute path on disk
    filename TEXT NOT NULL,
    taken_at TEXT,                  -- ISO8601, nullable
    latitude REAL,                  -- nullable
    longitude REAL,                 -- nullable
    embedding BLOB NOT NULL,        -- CLIP ViT-B-32, 512 x float32, L2-normalized
    face_cluster_ids TEXT,          -- JSON array of strings, e.g. '["p1","p2"]'
    object_tags TEXT,               -- JSON array of strings, e.g. '["dog"]'
    burst_group_id TEXT             -- nullable; shared id for near-duplicates
);

CREATE TABLE IF NOT EXISTS face_clusters (
    cluster_id TEXT PRIMARY KEY,
    label TEXT,                     -- nullable, empty for MVP
    photo_count INTEGER NOT NULL
);