#!/usr/bin/env python3
"""Remove the Gemini "✦" watermark baked into every (Gemini-generated) photo
source `_src/<env>/<variant>/{base,Base}.png`.

All sources are 1536x2752 portrait with the ✦ at a fixed bottom-right position,
so we LaMa-inpaint a small fixed box over it and overwrite base.png — keeping the
original as `*_wm.png` for reversibility. Run this BEFORE illustrate_all / warp_batch
so both the photo and the illustrated decors come out watermark-free.

Usage:
    python clean_watermark.py
"""
import os

import numpy as np
from PIL import Image

from split_layers import _lama_inpaint, build_lama

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "_src")

# ✦ box as fractions of the 1536x2752 source — generous enough to swallow the
# soft glow around the mark. Centred on (~0.917, ~0.954), the fixed Gemini spot.
BOX = (0.86, 0.92, 0.975, 0.985)


def find_bases(root):
    out = []
    for dp, _, fs in os.walk(root):
        for f in fs:
            if f.lower() == "base.png":
                out.append(os.path.join(dp, f))
    return sorted(out)


def main():
    bases = find_bases(SRC)
    if not bases:
        print(f"No base.png under {SRC}")
        return
    print(f"{len(bases)} source(s). Loading LaMa...", flush=True)
    lama = build_lama()
    for b in bases:
        im = Image.open(b).convert("RGB")
        w, h = im.size
        rgb = np.array(im)
        mask = np.zeros((h, w), np.uint8)
        x0, y0, x1, y1 = (int(w * BOX[0]), int(h * BOX[1]),
                          int(w * BOX[2]), int(h * BOX[3]))
        mask[y0:y1, x0:x1] = 255
        cleaned = _lama_inpaint(lama, rgb, mask)
        backup = os.path.splitext(b)[0] + "_wm.png"
        if not os.path.exists(backup):
            im.save(backup)  # keep the original (watermarked) for reversibility
        Image.fromarray(cleaned).save(b)
        print(f"-> cleaned {os.path.relpath(b, SRC)}", flush=True)
    print(f"All done: {len(bases)} source(s) de-watermarked.", flush=True)


if __name__ == "__main__":
    main()
