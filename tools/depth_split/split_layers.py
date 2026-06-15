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


def split_image(input_path, layers=4, feather=10, invert=False, radius=None,
                out=None, pipe=None):
    """Write N parallax layers next to (or into --out) the input. Returns (dir, n).

    Each layer's RGB is the photo with everything *nearer* than that layer
    inpainted away, so the layer's feathered edge fades into a plausible
    background (no hard cut-out seam) when it parallax-shifts. The band mask is
    eroded a touch (drop the background halo around the object) then feathered
    generously, and the back layer (0) is a fully-opaque inpainted plate.
    """
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
    if radius is None:
        radius = max(6, w // 220)  # inpaint reach scales with image size

    for li in range(n):
        lo, hi = bounds[li], bounds[li + 1]
        # Plane RGB: erase (inpaint) everything strictly nearer than this plane,
        # so the revealed area around the plane is plausible background.
        nearer = (depth >= hi).astype(np.uint8) * 255
        if nearer.any():
            mask = cv2.dilate(nearer, kernel, iterations=2)
            plane_rgb = cv2.inpaint(rgb, mask, radius, cv2.INPAINT_TELEA)
        else:
            plane_rgb = rgb.copy()

        if li == 0:
            alpha = np.full((h, w), 255, np.uint8)  # back plate: fully opaque
        else:
            band = (((depth >= lo) & (depth < hi)).astype(np.uint8)) * 255
            band = cv2.morphologyEx(band, cv2.MORPH_OPEN, kernel)
            band = cv2.erode(band, kernel, iterations=1)  # trim background halo
            alpha = cv2.GaussianBlur(band, (0, 0), feather)

        rgba = np.dstack([plane_rgb, alpha])
        Image.fromarray(rgba, "RGBA").save(os.path.join(out_dir, f"{li}.png"))

    return out_dir, n


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("--layers", type=int, default=4)
    ap.add_argument("--feather", type=int, default=10, help="edge feather radius (px)")
    ap.add_argument("--radius", type=int, default=None, help="inpaint reach (px); auto if unset")
    ap.add_argument("--out", default=None)
    ap.add_argument("--invert", action="store_true", help="flip near/far if swapped")
    args = ap.parse_args()

    print("Estimating depth (first run downloads the ~100 MB model)...", flush=True)
    out_dir, n = split_image(
        args.input, args.layers, args.feather, args.invert, args.radius, args.out
    )
    print(f"Done: {n} layers in {out_dir}", flush=True)


if __name__ == "__main__":
    main()
