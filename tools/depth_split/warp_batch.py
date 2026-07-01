"""Generate depth-warp assets (full.webp + depth.webp) for EVERY scene, both the
photographic and the illustrated tree, reusing one loaded depth model. Removes
the legacy numbered cut layers afterwards so each scene ships only the warp pair.

Run:  python warp_batch.py
"""

import argparse
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import split_layers as SL  # noqa: E402
import warp_assets as WA  # noqa: E402

ENVS = ["space", "underwater", "forest", "beach", "library", "mountain",
        "desert", "aurora", "fields",
        # Seasonal "marronnier" worlds (single variant each).
        "christmas", "halloween", "april"]


def src_for(env: str, v: int, kind: str) -> str | None:
    base = f"tools/depth_split/_src/{env}/{v}"
    if kind == "photo":
        for n in ("Base.png", "base.png"):
            if os.path.exists(f"{base}/{n}"):
                return f"{base}/{n}"
    else:  # illustrated
        if os.path.exists(f"{base}/illus.png"):
            return f"{base}/illus.png"
    return None


def clean_layers(d: str) -> None:
    for f in glob.glob(d + "/*.webp"):
        stem = os.path.splitext(os.path.basename(f))[0]
        if re.fullmatch(r"\d+", stem):  # 0.webp, 1.webp … (the old cut layers)
            os.remove(f)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--only",
        default="",
        help="comma-separated env names to limit to (e.g. "
        "'christmas,halloween,april'); default = all scenes",
    )
    args = ap.parse_args()
    only = {s for s in args.only.split(",") if s}
    envs = [e for e in ENVS if not only or e in only]

    pipe = SL.build_pipe()
    done = 0
    for env in envs:
        for v in (0, 1, 2):
            if not os.path.isdir(f"tools/depth_split/_src/{env}/{v}"):
                continue
            for kind, root in (("photo", "photo"), ("illustrated", "illustrated")):
                src = src_for(env, v, kind)
                if not src:
                    print(f"[skip] {root} {env}/{v}: no source", flush=True)
                    continue
                out = f"assets/{root}/{env}/{v}"
                try:
                    WA.gen(src, out, mesh_cols=100, pipe=pipe)
                    clean_layers(out)
                    done += 1
                except Exception as ex:  # noqa: BLE001
                    print(f"[FAIL] {root} {env}/{v}: {ex}", flush=True)
    del pipe
    if hasattr(SL, "_free"):
        SL._free()
    print(f"[warp_batch] done: {done} scene-trees", flush=True)


if __name__ == "__main__":
    main()
