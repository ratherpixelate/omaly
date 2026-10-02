"""Object / pet tagging with YOLOv8-nano (COCO classes).

NOTE: ultralytics downloads yolov8n.pt on first use. Run once with internet
before the demo, or drop yolov8n.pt next to where you run the script.
"""
from ultralytics import YOLO

from . import DEVICE, load_rgb

CONF = 0.35
SKIP = {"person"}  # people are handled by face clustering

_model = None


def tag_image(path) -> list[str]:
    """Return sorted unique COCO class names detected in the image."""
    global _model
    if _model is None:
        _model = YOLO("yolov8n.pt")
    r = _model.predict(load_rgb(path, 1280), conf=CONF, device=DEVICE, verbose=False)[0]
    names = {r.names[int(c)] for c in r.boxes.cls.tolist()}
    return sorted(names - SKIP)