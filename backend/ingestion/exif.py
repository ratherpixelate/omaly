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

    if not taken:
        import re
        from pathlib import Path
        p = Path(path)
        # 1. WhatsApp format: YYYY-MM-DD at HH.MM.SS
        m = re.search(r"(\d{4}-\d{2}-\d{2})\s+at\s+(\d{2})\.(\d{2})\.(\d{2})", p.name)
        if m:
            taken = f"{m.group(1)}T{m.group(2)}:{m.group(3)}:{m.group(4)}"
        else:
            # 2. ISO/compact date in filename: YYYY-MM-DD or YYYYMMDD
            m2 = re.search(r"(\d{4})[-_]?(\d{2})[-_]?(\d{2})", p.name)
            if m2 and 1990 <= int(m2.group(1)) <= 2030 and 1 <= int(m2.group(2)) <= 12 and 1 <= int(m2.group(3)) <= 31:
                taken = f"{m2.group(1)}-{m2.group(2)}-{m2.group(3)}T12:00:00"
            elif p.exists():
                try:
                    taken = datetime.fromtimestamp(p.stat().st_mtime).strftime("%Y-%m-%dT%H:%M:%S")
                except Exception:
                    pass

    return taken, lat, lon