"""EXIF extraction: (taken_at ISO8601, latitude, longitude). Never raises."""
import math
from datetime import datetime

import exifread
from PIL import Image


def _fmt_date(s):
    s = str(s).strip().replace("\x00", "")
    for fmt in ("%Y:%m:%d %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y:%m:%d"):
        try:
            return datetime.strptime(s, fmt).isoformat()
        except ValueError:
            pass
    return None


def _dms(vals, ref):
    d, m, s = (float(v) for v in vals)
    out = d + m / 60 + s / 3600
    if not math.isfinite(out):
        return None
    return -out if str(ref).upper().startswith(("S", "W")) else out


def _pillow(path):
    taken = lat = lon = None
    with Image.open(path) as img:
        ex = img.getexif()
        if not ex:
            return None, None, None
        sub = ex.get_ifd(0x8769)
        raw = sub.get(36867) or sub.get(36868) or ex.get(306)
        taken = _fmt_date(raw) if raw else None
        gps = ex.get_ifd(0x8825)
        if gps.get(2) and gps.get(4):
            lat = _dms(gps[2], gps.get(1, "N"))
            lon = _dms(gps[4], gps.get(3, "E"))
    return taken, lat, lon


def _exifread(path):
    taken = lat = lon = None
    with open(path, "rb") as f:
        t = exifread.process_file(f, details=False)
    raw = t.get("EXIF DateTimeOriginal") or t.get("Image DateTime")
    taken = _fmt_date(raw) if raw else None
    if "GPS GPSLatitude" in t and "GPS GPSLongitude" in t:
        lat = _dms(t["GPS GPSLatitude"].values, t.get("GPS GPSLatitudeRef", "N"))
        lon = _dms(t["GPS GPSLongitude"].values, t.get("GPS GPSLongitudeRef", "E"))
    return taken, lat, lon


def extract_exif(path):
    """Pillow first, exifread fills gaps. Returns (taken_at|None, lat|None, lon|None)."""
    taken = lat = lon = None
    for fn in (_pillow, _exifread):
        try:
            t, la, lo = fn(path)
            taken = taken or t
            if lat is None and la is not None and lo is not None:
                lat, lon = la, lo
        except Exception:
            pass
        if taken and lat is not None:
            break
    return taken, lat, lon