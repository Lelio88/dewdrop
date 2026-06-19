"""Depth-warp asset generator — the clean alternative to layer cutting.

Instead of cutting an image into discrete parallax layers (which forces an
inpaint of the disoccluded background that, once revealed by parallax, shows as
a halo / ghost / aura — see sam_split_poc.py's long battle), we ship the WHOLE
image plus a depth map. The Flutter side renders the image as a continuous
`drawVertices` mesh, displacing each vertex's texture coordinate by
`depth * tilt`. The mesh STRETCHES at depth discontinuities (never tears), so
there is no hole to fill and therefore no inpaint artefact at all. Thin
structures (palm fronds) get a soft partial displacement — exactly where matting
failed.

Per scene we write, next to the source:
  - `full.webp`  : the full image (no cutting), max 1280 wide.
  - `depth.webp` : a small LOSSLESS grayscale depth map at the MESH resolution
                   (near = white). The runtime decodes it straight into the mesh
                   grid, so depth.webp's resolution == the warp mesh resolution.

Usage:
  python warp_assets.py <src_image> <out_dir> [--cols 96]
  # or import gen() and loop over scenes.
"""

import argparse
import os
import sys

import cv2
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import split_layers as SL  # noqa: E402  (reuse the depth model + guided filter)

MAX_W = 1280


def gen(src: str, out_dir: str, mesh_cols: int = 96, pipe=None) -> tuple[int, int]:
    img = Image.open(src).convert("RGB")
    if img.width > MAX_W:
        img = img.resize((MAX_W, round(img.height * MAX_W / img.width)), Image.LANCZOS)
    rgb = np.array(img)
    h, w = rgb.shape[:2]
    os.makedirs(out_dir, exist_ok=True)

    # 1) Full image — no cutting. q76 is visually indistinguishable from q88 here
    # (verified on the worst case: palm fronds + sky gradient) at ~38% less size.
    img.save(os.path.join(out_dir, "full.webp"), "WEBP", quality=76, method=6)

    # 2) Depth (DA-V2-Large) + edge-aware guided refine, normalised to [0,1].
    own_pipe = pipe is None
    if own_pipe:
        pipe = SL.build_pipe()
    depth = SL.estimate_depth(img, pipe)
    depth = cv2.resize(depth, (w, h), interpolation=cv2.INTER_CUBIC)
    guide = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY).astype(np.float32) / 255.0
    depth = np.clip(
        SL._guided_filter(guide, depth, radius=max(8, w // 64), eps=1e-4), 0.0, 1.0
    )
    dn = (depth - depth.min()) / (depth.max() - depth.min() + 1e-6)

    # 3) Downsample the depth to the mesh grid and save LOSSLESS grayscale.
    gh = max(2, round(mesh_cols * h / w))
    grid = cv2.resize(dn, (mesh_cols, gh), interpolation=cv2.INTER_AREA)
    Image.fromarray((grid * 255.0).clip(0, 255).astype(np.uint8), "L").save(
        os.path.join(out_dir, "depth.webp"), "WEBP", lossless=True
    )
    if own_pipe:
        del pipe
        SL._free() if hasattr(SL, "_free") else None
    print(f"[warp] {out_dir}: full.webp + depth.webp (mesh {mesh_cols}x{gh})", flush=True)
    return mesh_cols, gh


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("out_dir")
    ap.add_argument("--cols", type=int, default=96)
    args = ap.parse_args()
    gen(args.src, args.out_dir, args.cols)


if __name__ == "__main__":
    main()
