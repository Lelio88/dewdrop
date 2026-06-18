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

MODEL = "depth-anything/Depth-Anything-V2-Large-hf"

# ── SDXL inpainting (engine="sdxl") ──────────────────────────────────────────
# Prompt-guided diffusion fill of the "fond perdu" behind removed foreground.
# Far more coherent than LaMa on large disocclusion holes, at the cost of speed.
SDXL_MODEL = "diffusers/stable-diffusion-xl-1.0-inpainting-0.1"

# We want a plausible empty background in the hole — never a new subject, person,
# text or frame.
SDXL_NEGATIVE = (
    "person, people, face, hands, animal, text, watermark, signature, logo, "
    "frame, border, blurry, lowres, low quality, jpeg artifacts, deformed, "
    "distorted, cartoon, illustration, painting"
)

# SDXL is trained at ~1024 px. We run the fill at that long edge, then composite
# the untouched (kept) pixels back at full resolution, so only the inpainted
# region is ever resampled.
SDXL_LONG_EDGE = 1024


def build_pipe():
    """Load the depth-estimation pipeline once (reuse it across images). Uses the
    GPU when a CUDA build of torch is installed, else CPU."""
    try:
        import torch
        from transformers import pipeline
    except ImportError:
        sys.exit(
            "transformers/torch missing. Install with:\n"
            "  pip install torch --index-url https://download.pytorch.org/whl/cpu\n"
            "  pip install -r requirements.txt"
        )
    device = 0 if torch.cuda.is_available() else -1
    return pipeline("depth-estimation", model=MODEL, device=device)


def estimate_depth(image: Image.Image, pipe) -> np.ndarray:
    """HxW float32 depth in [0, 1], 1.0 = nearest."""
    out = pipe(image)
    return np.array(out["depth"].convert("L"), dtype=np.float32) / 255.0


def _guided_filter(guide, src, radius=16, eps=1e-3):
    """Edge-preserving filter (He et al., 2010): smooth `src` while snapping its
    transitions onto `guide`'s edges. `guide` and `src` are float32 HxW in [0,1].

    Two uses here: (a) refine the coarse Depth-Anything map onto the real image
    edges so layer cuts follow object silhouettes (kills the "staircase" seams),
    and (b) feather layer alphas along those silhouettes instead of smearing a
    uniform Gaussian halo across the cut. Built on cv2.boxFilter (no extra dep)."""
    r = int(max(1, radius))
    d = (2 * r + 1, 2 * r + 1)
    mean_I = cv2.boxFilter(guide, -1, d)
    mean_p = cv2.boxFilter(src, -1, d)
    mean_Ip = cv2.boxFilter(guide * src, -1, d)
    cov_Ip = mean_Ip - mean_I * mean_p
    mean_II = cv2.boxFilter(guide * guide, -1, d)
    var_I = mean_II - mean_I * mean_I
    a = cov_Ip / (var_I + eps)
    b = mean_p - a * mean_I
    mean_a = cv2.boxFilter(a, -1, d)
    mean_b = cv2.boxFilter(b, -1, d)
    return mean_a * guide + mean_b


def build_lama():
    """Load the LaMa inpainting model once (reuse it across images)."""
    try:
        from simple_lama_inpainting import SimpleLama
    except ImportError:
        sys.exit(
            "simple-lama-inpainting missing. Install it (deps already present):\n"
            "  pip install simple-lama-inpainting --no-deps"
        )
    return SimpleLama()


def _lama_inpaint(lama, rgb: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """Inpaint the masked (255) region of `rgb` with LaMa, leaving the rest of
    the pixels exact. LaMa reconstructs a plausible background behind removed
    foreground far better than classical cv2.inpaint (no smeared "trace")."""
    out = np.array(
        lama(Image.fromarray(rgb, "RGB"), Image.fromarray(mask, "L")).convert("RGB")
    )
    if out.shape[:2] != rgb.shape[:2]:
        out = cv2.resize(out, (rgb.shape[1], rgb.shape[0]), interpolation=cv2.INTER_LINEAR)
    keep = (mask == 0)[:, :, None]
    return np.where(keep, rgb, out).astype(np.uint8)


def build_sdxl(model=SDXL_MODEL):
    """Load the SDXL inpainting pipeline once, tuned for ~6 GB VRAM (fp16 +
    sequential CPU offload + VAE tiling). Reuse it across images."""
    try:
        import torch
        from diffusers import AutoPipelineForInpainting
    except ImportError:
        sys.exit(
            "diffusers/accelerate missing. Install them in the venv:\n"
            "  pip install diffusers accelerate"
        )
    pipe = AutoPipelineForInpainting.from_pretrained(
        model, torch_dtype=torch.float16, variant="fp16"
    )
    pipe.set_progress_bar_config(disable=True)
    pipe.enable_model_cpu_offload()  # keep peak VRAM under ~6 GB
    pipe.enable_vae_tiling()
    return pipe


def _sdxl_inpaint(pipe, rgb, mask, prompt, negative=SDXL_NEGATIVE,
                  steps=30, guidance=7.0, seed=0):
    """Fill the masked (255) region of `rgb` with prompt-guided SDXL inpainting,
    leaving the unmasked pixels byte-exact. Runs at SDXL_LONG_EDGE then resamples
    the result back; only the masked pixels are taken from the diffusion output."""
    import torch

    h, w = rgb.shape[:2]
    scale = min(1.0, SDXL_LONG_EDGE / max(h, w))
    gw = max(8, int(round(w * scale)) // 8 * 8)
    gh = max(8, int(round(h * scale)) // 8 * 8)
    img = Image.fromarray(rgb, "RGB").resize((gw, gh), Image.LANCZOS)
    m = Image.fromarray(mask, "L").resize((gw, gh), Image.NEAREST)
    gen = torch.Generator(device="cuda").manual_seed(seed)
    res = pipe(
        prompt=prompt or "photorealistic natural background, high detail",
        negative_prompt=negative,
        image=img,
        mask_image=m,
        width=gw,
        height=gh,
        num_inference_steps=steps,
        guidance_scale=guidance,
        strength=1.0,
        generator=gen,
    ).images[0]
    out = np.array(res.convert("RGB").resize((w, h), Image.LANCZOS))
    keep = (mask == 0)[:, :, None]
    return np.where(keep, rgb, out).astype(np.uint8)


def split_image(input_path, layers=4, feather=10, invert=False, radius=None,
                out=None, pipe=None, lama=None, max_width=1280,
                engine="lama", sdxl=None, prompt=None, negative=SDXL_NEGATIVE):
    """Write N parallax layers next to (or into --out) the input. Returns (dir, n).

    Each layer's RGB is the photo with everything *nearer* than that layer
    inpainted away (with LaMa), so the layer's feathered edge fades into a
    plausible reconstructed background (no smeared "trace") when it parallax-
    shifts. The band mask is eroded a touch (drop the background halo around the
    object) then feathered generously, and the back layer (0) is a fully-opaque
    inpainted plate. The source is downscaled to [max_width] first — it matches
    the shipped WebP resolution and keeps LaMa tractable on CPU.
    """
    if pipe is None:
        pipe = build_pipe()
    if engine == "sdxl":
        if sdxl is None:
            sdxl = build_sdxl()
    elif lama is None:
        lama = build_lama()

    img = Image.open(input_path).convert("RGB")
    if img.width > max_width:
        nh = round(img.height * max_width / img.width)
        img = img.resize((max_width, nh), Image.LANCZOS)
    rgb = np.array(img)
    h, w = rgb.shape[:2]
    guide = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY).astype(np.float32) / 255.0

    depth = estimate_depth(img, pipe)
    depth = cv2.resize(depth, (w, h), interpolation=cv2.INTER_CUBIC)
    if invert:
        depth = 1.0 - depth
    # Edge-aware refinement: snap the coarse depth boundaries onto real image
    # edges (guide = luminance) so the layer cuts follow object silhouettes
    # instead of stepping along the low-res depth map ("staircase" seams).
    depth = np.clip(
        _guided_filter(guide, depth, radius=max(8, w // 64), eps=1e-4), 0.0, 1.0
    )

    n = max(2, layers)
    qs = [float(np.quantile(depth, i / n)) for i in range(1, n)]
    bounds = [0.0, *qs, 1.0 + 1e-6]

    out_dir = out or os.path.dirname(os.path.abspath(input_path))
    os.makedirs(out_dir, exist_ok=True)
    feather = max(1, feather)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))

    for li in range(n):
        lo, hi = bounds[li], bounds[li + 1]
        # Plane RGB: erase (inpaint) everything strictly nearer than this plane,
        # so the revealed area around the plane is plausible background.
        nearer = (depth >= hi).astype(np.uint8) * 255
        if nearer.any():
            mask = cv2.dilate(nearer, kernel, iterations=2)
            if engine == "sdxl":
                plane_rgb = _sdxl_inpaint(sdxl, rgb, mask, prompt, negative)
            else:
                plane_rgb = _lama_inpaint(lama, rgb, mask)
        else:
            plane_rgb = rgb.copy()

        if li == 0:
            alpha = np.full((h, w), 255, np.uint8)  # back plate: fully opaque
        else:
            band = (((depth >= lo) & (depth < hi)).astype(np.uint8)) * 255
            band = cv2.morphologyEx(band, cv2.MORPH_OPEN, kernel)
            band = cv2.erode(band, kernel, iterations=1)  # trim background halo
            # Edge-aware feather: a guided filter hugs the object silhouette
            # (guide = luminance) instead of the uniform GaussianBlur halo that
            # smears across the cut. A small Gaussian then softens residual steps.
            bf = _guided_filter(guide, band.astype(np.float32) / 255.0,
                                radius=feather * 2, eps=1e-3)
            bf = cv2.GaussianBlur(bf, (0, 0), max(1.0, feather / 3))
            alpha = np.clip(bf * 255.0, 0, 255).astype(np.uint8)

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
    ap.add_argument("--engine", choices=["lama", "sdxl"], default="lama",
                    help="hole-fill engine: LaMa (fast) or SDXL inpaint (prompt-guided)")
    ap.add_argument("--prompt", default=None, help="SDXL fill prompt (engine=sdxl)")
    args = ap.parse_args()

    print("Estimating depth (first run downloads Depth-Anything-V2-Large, ~1.3 GB)...", flush=True)
    out_dir, n = split_image(
        args.input, args.layers, args.feather, args.invert, args.radius, args.out,
        engine=args.engine, prompt=args.prompt,
    )
    print(f"Done: {n} layers in {out_dir}", flush=True)


if __name__ == "__main__":
    main()
