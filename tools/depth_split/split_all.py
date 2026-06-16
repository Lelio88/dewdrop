#!/usr/bin/env python3
"""Batch: split every `base.png` into parallax layers.

Loads the depth model once, then processes all scenes. Case-insensitive on the
`base.png` name. Re-run any time you add new base images.

NOTE (asset pipeline): the shipped layers in `assets/photo/<env>/<variant>/` are
**downscaled WebP** (`0.webp … N.webp`, ~1280px, alpha preserved) to keep the
APK small — the full-res `base.png` sources now live OUT of the bundle under
`tools/depth_split/_src/<env>/<variant>/base.png`. Pass that as the root, e.g.
`python split_all.py tools/depth_split/_src`, then convert/downscale the emitted
PNG layers to WebP into `assets/photo/...` (see CREDITS/build notes). TODO: fold
the downscale+WebP export and the source→assets path mapping into split_layers.

Usage:
    python split_all.py [photo_root] [--layers 3] [--feather 6]
"""
import argparse
import os

from split_layers import build_pipe, split_image

DEFAULT_ROOT = os.path.normpath(
    os.path.join(os.path.dirname(__file__), "..", "..", "assets", "photo")
)

# Per-environment split settings. The algorithm is shared; only these knobs
# differ per scene. Landscapes with real depth get more planes (smaller
# per-plane shift → softer parallax) and a moderate feather; space has
# unreliable monocular depth (stars/void), so few planes + a big feather hide
# bad cuts (and the renderer flattens its parallax — see _depthStrength).
# Keys: layers, feather, radius (None = auto), invert.
DEFAULTS = {"layers": 4, "feather": 10, "radius": None, "invert": False}
SCENE_SETTINGS = {
    "space": {"layers": 2, "feather": 16, "radius": 12},
    "library": {"layers": 3, "feather": 10},
    "underwater": {"layers": 4, "feather": 11},
    "forest": {"layers": 4, "feather": 10},
    "beach": {"layers": 4, "feather": 10},
    "desert": {"layers": 4, "feather": 12},
    "aurora": {"layers": 4, "feather": 12},
    "mountain": {"layers": 5, "feather": 10},
}


def settings_for(env):
    s = dict(DEFAULTS)
    s.update(SCENE_SETTINGS.get(env, {}))
    return s


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
    ap.add_argument("--layers", type=int, default=None,
                    help="force a layer count for all scenes (else per-scene defaults)")
    ap.add_argument("--feather", type=int, default=None,
                    help="force a feather for all scenes (else per-scene defaults)")
    args = ap.parse_args()

    bases = find_bases(args.root)
    if not bases:
        print(f"No base.png found under {args.root}")
        return

    print(f"Found {len(bases)} base image(s). Loading model once...", flush=True)
    pipe = build_pipe()
    for b in bases:
        rel = os.path.relpath(b, args.root)
        env = rel.replace("\\", "/").split("/")[0]
        s = settings_for(env)
        # Explicit CLI flags override the per-scene defaults.
        n = args.layers if args.layers is not None else s["layers"]
        feather = args.feather if args.feather is not None else s["feather"]
        print(f"-> {rel}  (env={env}, layers={n}, feather={feather})", flush=True)
        split_image(b, layers=n, feather=feather, invert=s["invert"],
                    radius=s["radius"], pipe=pipe)
    print(f"All done: {len(bases)} scene(s) split.", flush=True)


if __name__ == "__main__":
    main()
