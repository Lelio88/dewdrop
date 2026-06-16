#!/usr/bin/env python3
"""Export the split PNG layers in `_src/<env>/<variant>/` to the shipped WebP
assets in `assets/photo/<env>/<variant>/` (alpha preserved). Run after
`split_all.py`. Layers are already at the shipped width, so this is a pure
format conversion — no resize.

Usage: python export_webp.py [--quality 82]
"""
import argparse
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "_src")
DST = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "photo"))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quality", type=int, default=82)
    args = ap.parse_args()

    count, total = 0, 0
    for env in sorted(os.listdir(SRC)):
        env_dir = os.path.join(SRC, env)
        if not os.path.isdir(env_dir):
            continue
        for variant in sorted(os.listdir(env_dir)):
            vdir = os.path.join(env_dir, variant)
            if not os.path.isdir(vdir):
                continue
            out_dir = os.path.join(DST, env, variant)
            os.makedirs(out_dir, exist_ok=True)
            # Drop stale numbered layers so a re-split with fewer layers stays clean.
            for old in os.listdir(out_dir):
                if old.endswith(".webp") and os.path.splitext(old)[0].isdigit():
                    os.remove(os.path.join(out_dir, old))
            for f in sorted(os.listdir(vdir)):
                stem, ext = os.path.splitext(f)
                if ext.lower() != ".png" or not stem.isdigit():
                    continue
                img = Image.open(os.path.join(vdir, f)).convert("RGBA")
                out = os.path.join(out_dir, stem + ".webp")
                img.save(out, "WEBP", quality=args.quality, method=6)
                kb = os.path.getsize(out) // 1024
                count += 1
                total += os.path.getsize(out)
                print(f"  {env}/{variant}/{stem}.webp  ({kb} KB)", flush=True)
    print(f"Done: {count} layers, {total / 1e6:.1f} MB total.", flush=True)


if __name__ == "__main__":
    main()
