"""CLIP ViT-B-32 (openai) image embeddings: 512-d, float32, L2-normalized."""
import numpy as np
import open_clip
import torch

from . import DEVICE, EMBED_DIM, load_rgb

_state: dict = {}


def _load():
    if not _state:
        device = DEVICE
        model, _, preprocess = open_clip.create_model_and_transforms(
            "ViT-B-32", pretrained="openai")
        model.eval().to(device)
        _state.update(model=model, preprocess=preprocess, device=device)
        print(f"CLIP ViT-B-32 loaded on {device}")
    return _state


@torch.no_grad()
def _encode(tensors) -> np.ndarray:
    s = _load()
    x = torch.stack(tensors).to(s["device"])
    f = s["model"].encode_image(x)
    f = f / f.norm(dim=-1, keepdim=True)
    out = f.cpu().numpy().astype("float32")
    assert out.shape[1] == EMBED_DIM, f"unexpected dim {out.shape[1]}"
    return out


def embed_files(paths, batch_size: int = 16):
    """Yield one list per batch of (path, embedding | None, error | None).

    A bad file only fails itself; it never kills the batch or the run.
    """
    for i in range(0, len(paths), batch_size):
        results, ok = [], []
        for p in paths[i:i + batch_size]:
            try:
                ok.append((p, _load()["preprocess"](load_rgb(p))))
            except Exception as e:
                results.append((p, None, repr(e)))
        if ok:
            try:
                embs = _encode([t for _, t in ok])
                results += [(p, e, None) for (p, _), e in zip(ok, embs)]
            except Exception:  # batch failed: retry one by one
                for p, t in ok:
                    try:
                        results.append((p, _encode([t])[0], None))
                    except Exception as e:
                        results.append((p, None, repr(e)))
        yield results