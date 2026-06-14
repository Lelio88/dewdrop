#!/usr/bin/env python3
"""Split a single photo into depth-ordered parallax layers for DewDrop.

Uses Depth Anything V2 (monocular depth estimation) to estimate per-pixel
distance, slices the image into N layers (0 = farthest .. N-1 = nearest) with
feathered transparency, and inpaints the holes behind the foreground so the
back layer stays fully opaque.

Usage:
    python split_layers.py path/to/base.png [--layers 3] [--feather 6] [--out DIR]

Outputs `0.png` .. `(N-1).png` next to the input (or into --out). The engine
ignores `base.png`, so keep it as your source. See split_all.py for batch.
"""
import argparse
import os
import sys

import cv2
import numpy as np
from PIL import Image

MODEL = "depth-anything/Depth-Anything-V2-Small-hf"


def build_pipe():
    """Load the depth-estimation pipeline once (reuse it across images)."""
    try:
        from transformers import pipeline
    except ImportError:
        sys.exit(
            "transformers/torch missing. Install with:\n"
            "  pip install torch --index-url https://download.pytorch.org/whl/cpu\n"
            "  pip install -r requirements.txt"
        )
    return pipeline("depth-estimation", model=MODEL)


def estimate_depth(image: Image.Image, pipe) -> np.ndarray:
    """HxW float32 depth in [0, 1], 1.0 = nearest."""
    out = pipe(image)
    return np.array(out["depth"].convert("L"), dtype=np.float32) / 255.0


def split_image(input_path, layers=3, feather=6, invert=False, out=None, pipe=None):
    """Write N parallax layers next to (or into --out) the input. Returns (dir, n)."""
    if pipe is None:
        pipe = build_pipe()

    img = Image.open(input_path).convert("RGB")
    rgb = np.array(img)
    h, w = rgb.shape[:2]

    depth = estimate_depth(img, pipe)
    depth = cv2.resize(depth, (w, h), interpolation=cv2.INTER_CUBIC)
    if invert:
        depth = 1.0 - depth

    n = max(2, layers)
    qs = [float(np.quantile(depth, i / n)) for i in range(1, n)]
    bounds = [0.0, *qs, 1.0 + 1e-6]

    out_dir = out or os.path.dirname(os.path.abspath(input_path))
    os.makedirs(out_dir, exist_ok=True)
    feather = max(1, feather)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))

    for li in range(n):
        lo, hi = bounds[li], bounds[li + 1]
        if li == 0:
            nearer = (depth >= hi).astype(np.uint8) * 255
            base = cv2.inpaint(rgb, nearer, 5, cv2.INPAINT_TELEA) if nearer.any() else rgb.copy()
            alpha = np.full((h, w), 255, np.uint8)
            rgba = np.dstack([base, alpha])
        else:
            band = (((depth >= lo) & (depth < hi)).astype(np.uint8)) * 255
            band = cv2.morphologyEx(band, cv2.MORPH_OPEN, kernel)
            alpha = cv2.GaussianBlur(band, (0, 0), feather)
            rgba = np.dstack([rgb, alpha])
        Image.fromarray(rgba, "RGBA").save(os.path.join(out_dir, f"{li}.png"))

    return out_dir, n


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("--layers", type=int, default=3)
    ap.add_argument("--feather", type=int, default=6, help="edge feather radius (px)")
    ap.add_argument("--out", default=None)
    ap.add_argument("--invert", action="store_true", help="flip near/far if swapped")
    args = ap.parse_args()

    print("Estimating depth (first run downloads the ~100 MB model)...", flush=True)
    out_dir, n = split_image(
        args.input, args.layers, args.feather, args.invert, args.out
    )
    print(f"Done: {n} layers in {out_dir}", flush=True)


if __name__ == "__main__":
    main()
