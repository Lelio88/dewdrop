#!/usr/bin/env python3
"""Batch: split every `base.png` under assets/photo into parallax layers.

Loads the depth model once, then processes all scenes. Case-insensitive on the
`base.png` name. Re-run any time you add new base images.

Usage:
    python split_all.py [photo_root] [--layers 3] [--feather 6]
"""
import argparse
import os

from split_layers import build_pipe, split_image

DEFAULT_ROOT = os.path.normpath(
    os.path.join(os.path.dirname(__file__), "..", "..", "assets", "photo")
)


def find_bases(root):
    bases = []
    for dirpath, _, files in os.walk(root):
        for f in files:
            if f.lower() == "base.png":
                bases.append(os.path.join(dirpath, f))
    return sorted(bases)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root", nargs="?", default=DEFAULT_ROOT)
    ap.add_argument("--layers", type=int, default=3)
    ap.add_argument("--feather", type=int, default=6)
    args = ap.parse_args()

    bases = find_bases(args.root)
    if not bases:
        print(f"No base.png found under {args.root}")
        return

    print(f"Found {len(bases)} base image(s). Loading model once...", flush=True)
    pipe = build_pipe()
    for b in bases:
        rel = os.path.relpath(b, args.root)
        print(f"-> {rel}", flush=True)
        split_image(b, layers=args.layers, feather=args.feather, pipe=pipe)
    print(f"All done: {len(bases)} scene(s) split.", flush=True)


if __name__ == "__main__":
    main()
