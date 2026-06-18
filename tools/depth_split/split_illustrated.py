#!/usr/bin/env python3
"""Split each illustrated decor source `_src/<env>/<variant>/illus.png` into
parallax layers and export them to `assets/illustrated/<env>/<variant>/*.webp`
— the assets for DewDrop's "drawn" decor mode.

Mirrors the photo pipeline (split_all + export_webp) but reads `illus.png` and
writes under `assets/illustrated/`, reusing the same per-scene SCENE_SETTINGS so
the drawn and photo parallax behave identically (same layer count + feather, the
edge-aware DA-Large + guided-filter cut). The illustration IS the same scene as
the photo (img2img from the same source), so drawn and photo stay in lockstep.

Usage:
    python split_illustrated.py [--quality 82]
"""
import argparse
import os
import shutil

from PIL import Image

from split_all import settings_for
from split_layers import build_lama, build_pipe, split_image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "_src")
DST = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "illustrated"))


def find_illus(root):
    out = []
    for dp, _, fs in os.walk(root):
        for f in fs:
            if f.lower() == "illus.png":
                out.append(os.path.join(dp, f))
    return sorted(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quality", type=int, default=82)
    args = ap.parse_args()

    illus = find_illus(SRC)
    if not illus:
        print(f"No illus.png under {SRC}")
        return
    print(f"{len(illus)} illustration(s). Loading models...", flush=True)
    pipe = build_pipe()
    lama = build_lama()
    total = 0
    for ip in illus:
        rel = os.path.relpath(ip, SRC).replace("\\", "/").split("/")
        env, var = rel[0], rel[1]
        s = settings_for(env)
        tmp = os.path.join(os.path.dirname(ip), "_illus_layers")
        split_image(ip, layers=s["layers"], feather=s["feather"], invert=s["invert"],
                    radius=s["radius"], out=tmp, pipe=pipe, lama=lama)
        out_dir = os.path.join(DST, env, var)
        os.makedirs(out_dir, exist_ok=True)
        # Drop stale numbered layers so a re-split with fewer layers stays clean.
        for old in os.listdir(out_dir):
            if old.endswith(".webp") and os.path.splitext(old)[0].isdigit():
                os.remove(os.path.join(out_dir, old))
        for f in sorted(os.listdir(tmp)):
            stem, ext = os.path.splitext(f)
            if ext.lower() != ".png" or not stem.isdigit():
                continue
            img = Image.open(os.path.join(tmp, f)).convert("RGBA")
            img.save(os.path.join(out_dir, stem + ".webp"), "WEBP",
                     quality=args.quality, method=6)
            total += 1
        shutil.rmtree(tmp, ignore_errors=True)  # temp PNG layers, not shipped
        print(f"-> {env}/{var}  ({s['layers']} layers)", flush=True)
    print(f"All done: {total} illustrated layers -> {DST}", flush=True)


if __name__ == "__main__":
    main()
