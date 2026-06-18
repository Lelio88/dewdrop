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

from split_layers import build_lama, build_pipe, build_sdxl, split_image

DEFAULT_ROOT = os.path.normpath(
    os.path.join(os.path.dirname(__file__), "..", "..", "assets", "photo")
)

# Per-environment split settings. The algorithm is shared; only these knobs
# differ per scene. Layer alphas are cut edge-aware (a guided filter snaps them
# to real silhouettes — see split_layers._guided_filter), so landscapes now use
# a SMALL feather (~4): the large feather that used to smear over blocky cuts is
# no longer needed, and a small one keeps tree/ridge silhouettes crisp. Sky/void-
# heavy scenes (space, desert night, aurora) keep a larger feather — their
# monocular depth is unreliable and there are few real edges for the guided
# filter to snap to (space also flattens its parallax — see _depthStrength).
# Keys: layers, feather, radius (None = auto), invert.
DEFAULTS = {"layers": 4, "feather": 5, "radius": None, "invert": False}
SCENE_SETTINGS = {
    "space": {"layers": 2, "feather": 12, "radius": 12},
    "library": {"layers": 3, "feather": 4},
    "underwater": {"layers": 4, "feather": 5},
    "forest": {"layers": 4, "feather": 4},
    "beach": {"layers": 4, "feather": 4},
    "desert": {"layers": 4, "feather": 7},
    "aurora": {"layers": 4, "feather": 6},
    "mountain": {"layers": 5, "feather": 4},
}


def settings_for(env):
    s = dict(DEFAULTS)
    s.update(SCENE_SETTINGS.get(env, {}))
    return s


# Per-scene SDXL fill prompts (engine="sdxl"): they describe the BACKGROUND that
# should appear behind removed foreground — photoreal, no new subject. Keyed by
# "env", with optional "env/variant" overrides for variants that differ a lot.
SCENE_PROMPTS = {
    "space": "deep space background, distant stars, faint nebula, cosmic dust, dark sky, photorealistic",
    "underwater": "underwater ocean background, deep blue water, soft god rays, suspended particles, photorealistic",
    "forest": "dense forest background, tree trunks and foliage in shade, dappled sunlight, soft depth of field, photorealistic",
    "forest/1": "cherry blossom forest background, pink sakura branches, soft light, photorealistic",
    "forest/2": "rainforest canopy background, layered green treetops, mist, soft light, photorealistic",
    "beach": "tropical beach background, calm sea, clear blue sky, distant horizon, soft sand, photorealistic",
    "beach/1": "beach at sunset background, warm orange sky, calm sea, soft sand, photorealistic",
    "library": "cozy old library background, wooden bookshelves full of books, warm dim light, photorealistic",
    "mountain": "mountain landscape background, distant peaks, valley, soft haze, sky, photorealistic",
    "mountain/1": "mountain landscape at night background, dark peaks, starry sky, photorealistic",
    "desert": "desert background, rolling sand dunes, clear sky, soft haze, photorealistic",
    "desert/1": "desert at night background, sand dunes under a starry sky, photorealistic",
    "aurora": "night sky background with green aurora borealis, stars, snowy landscape, photorealistic",
    "aurora/1": "night sky background with magenta aurora borealis, stars, snowy landscape, photorealistic",
}


def prompt_for(env, variant):
    return SCENE_PROMPTS.get(
        f"{env}/{variant}",
        SCENE_PROMPTS.get(env, "photorealistic natural background, high detail"),
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
    ap.add_argument("--layers", type=int, default=None,
                    help="force a layer count for all scenes (else per-scene defaults)")
    ap.add_argument("--feather", type=int, default=None,
                    help="force a feather for all scenes (else per-scene defaults)")
    ap.add_argument("--engine", choices=["lama", "sdxl"], default="lama",
                    help="hole-fill engine: LaMa (fast) or SDXL inpaint (prompt-guided)")
    args = ap.parse_args()

    bases = find_bases(args.root)
    if not bases:
        print(f"No base.png found under {args.root}")
        return

    print(f"Found {len(bases)} base image(s). Loading models once...", flush=True)
    pipe = build_pipe()
    sdxl = lama = None
    if args.engine == "sdxl":
        sdxl = build_sdxl()
    else:
        lama = build_lama()
    for b in bases:
        rel = os.path.relpath(b, args.root)
        parts = rel.replace("\\", "/").split("/")
        env = parts[0]
        variant = parts[1] if len(parts) > 1 else "0"
        s = settings_for(env)
        # Explicit CLI flags override the per-scene defaults.
        n = args.layers if args.layers is not None else s["layers"]
        feather = args.feather if args.feather is not None else s["feather"]
        prompt = prompt_for(env, variant) if args.engine == "sdxl" else None
        print(f"-> {rel}  (env={env}, layers={n}, feather={feather}, engine={args.engine})",
              flush=True)
        split_image(b, layers=n, feather=feather, invert=s["invert"],
                    radius=s["radius"], pipe=pipe, lama=lama,
                    engine=args.engine, sdxl=sdxl, prompt=prompt)
    print(f"All done: {len(bases)} scene(s) split.", flush=True)


if __name__ == "__main__":
    main()
