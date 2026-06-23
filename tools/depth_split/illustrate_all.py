#!/usr/bin/env python3
"""Stylize every photo source into a watercolor-storybook illustration for
DewDrop's "drawn" decor mode.

For each `_src/<env>/<variant>/{base,Base}.png` this writes an `illus.png` next
to it (SDXL base img2img, one shared "aquarelle storybook" style). The denoise
`strength` is **per-scene**: textured land/interior scenes take a strong style,
while smooth/cosmic scenes (space, aurora, deep water) take a gentle one — a
strong style turns a starfield or an open sky into cheap generic clipart (see the
nuancier study). Then run `warp_batch.py` on the emitted `illus.png` to produce
the depth-warp pair `assets/illustrated/<env>/<v>/{full,depth}.webp`.

Usage:
    python illustrate_all.py            # all scenes
    HF_HUB_ENABLE_HF_TRANSFER=1 ...     # robust model download

Invariants:
- The illustration is img2img FROM the photo source, so the drawn scene is the
  *same scene* as the photo (DewDrop doctrine: one variant = one real scene,
  rendered in both Drawn and Photo).
- Tuned for ~6 GB VRAM: fp16 + sequential CPU offload + VAE tiling.
"""
import argparse
import os

import torch
from diffusers import AutoPipelineForImage2Image
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "_src")
MODEL = "stabilityai/stable-diffusion-xl-base-1.0"

STYLE = (
    "children's book watercolor illustration, soft hand-painted washes, "
    "cozy dreamy storybook art, gentle colors"
)
# Hard rule: NO humans on any decor (user requirement). Also ban the recurring
# img2img hallucinations (animals, free-standing dwellings) and any text/mark.
# We ban specific dwellings ("house, cottage, cabin…") but NOT "building/
# architecture/interior" — that would wreck the library decors (bookshelves,
# arches, fireplace are legit built interior, not a hallucinated cottage).
NEG = (
    "photo, photograph, photorealistic, realistic, 3d render, "
    "person, people, human, child, children, man, woman, boy, girl, figure, "
    "silhouette, crowd, "
    "animal, cat, dog, bird, pet, wildlife, "
    "house, cottage, cabin, hut, shed, tent, "
    "text, watermark, signature, logo, blurry, low quality, deformed"
)

# Per-scene denoise strength. Textured scenes take a strong stylization; smooth /
# cosmic scenes a gentle one (a strong style destroys a starfield / open sky).
STRENGTH = {
    "forest": 0.60, "library": 0.60, "fields": 0.60, "mountain": 0.58,
    "beach": 0.55, "desert": 0.52, "aurora": 0.45, "underwater": 0.45,
    "space": 0.35,
}
# Per-(env/variant) overrides for variants that differ from their scene default.
# Per-(env/variant) overrides. Gentler where a strong style drifts off the source
# (forest/2 must stay a canopy view) or destroys a starfield (desert night).
STRENGTH_VAR = {"desert/1": 0.40, "forest/2": 0.45}

# Scene words appended to the style prompt (img2img keeps the structure; the
# words just nudge coherence).
DESC = {
    "forest": "forest landscape", "library": "cozy library interior",
    "mountain": "mountain landscape", "beach": "tropical beach, sea and sky",
    "desert": "desert dunes", "aurora": "aurora borealis night sky",
    "underwater": "underwater ocean scene", "space": "deep space, stars, milky way",
    "fields": "summer countryside field, meadow and wheat, warm light",
}


def find_bases(root):
    out = []
    for dp, _, fs in os.walk(root):
        for f in fs:
            if f.lower() == "base.png":
                out.append(os.path.join(dp, f))
    return sorted(out)


def load1024(path):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    sc = 1024 / max(w, h)
    nw = max(8, int(round(w * sc)) // 8 * 8)
    nh = max(8, int(round(h * sc)) // 8 * 8)
    return im.resize((nw, nh), Image.LANCZOS)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--steps", type=int, default=34)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument(
        "--only",
        default="",
        help="comma-separated env names to limit to (e.g. 'fields'); "
        "default = all scenes",
    )
    args = ap.parse_args()

    only = {s for s in args.only.split(",") if s}
    bases = find_bases(SRC)
    if only:
        bases = [
            b
            for b in bases
            if os.path.relpath(b, SRC).replace("\\", "/").split("/")[0] in only
        ]
    if not bases:
        print(f"No base.png under {SRC}" + (f" for --only {only}" if only else ""))
        return
    print(f"{len(bases)} source(s). Loading SDXL base (img2img)...", flush=True)
    pipe = AutoPipelineForImage2Image.from_pretrained(
        MODEL, torch_dtype=torch.float16, variant="fp16"
    )
    pipe.set_progress_bar_config(disable=True)
    pipe.enable_model_cpu_offload()
    pipe.enable_vae_tiling()

    for b in bases:
        rel = os.path.relpath(b, SRC).replace("\\", "/").split("/")
        env = rel[0]
        var = rel[1] if len(rel) > 1 else "0"
        strength = STRENGTH_VAR.get(f"{env}/{var}", STRENGTH.get(env, 0.55))
        desc = DESC.get(env, "landscape")
        img = load1024(b)
        gen = torch.Generator(device="cuda").manual_seed(args.seed)
        res = pipe(
            prompt=f"{STYLE}, {desc}",
            image=img,
            strength=strength,
            guidance_scale=7.0,
            negative_prompt=NEG,
            num_inference_steps=args.steps,
            generator=gen,
        ).images[0]
        out = os.path.join(os.path.dirname(b), "illus.png")
        res.save(out)
        print(f"-> {env}/{var}  strength={strength}  -> {out}", flush=True)
    print(f"All done: {len(bases)} illustrated.", flush=True)


if __name__ == "__main__":
    main()
