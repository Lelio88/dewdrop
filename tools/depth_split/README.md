# depth_split — auto parallax layers

Turns a single photo (`base.png`) into depth-ordered layers (`0.png` = farthest
… `N-1.png` = nearest) with transparency, for DewDrop's photo decor parallax.

It estimates depth with **Depth Anything V2**, slices the image into N bands,
feathers the edges, and inpaints the holes behind the foreground so the back
layer is fully opaque.

## Setup (once)

```powershell
cd tools/depth_split
python -m venv .venv
.venv\Scripts\python -m pip install --upgrade pip
.venv\Scripts\python -m pip install torch --index-url https://download.pytorch.org/whl/cpu
.venv\Scripts\python -m pip install -r requirements.txt
```

## Use

```powershell
.venv\Scripts\python split_layers.py ..\..\assets\photo\forest\0\base.png --layers 3
```

Then rebuild the app — the new `0/1/2.png` are picked up automatically.
`base.png` is the source and is ignored by the engine (only `0.png`, `1.png`, …
are loaded). Use `--invert` if near/far come out swapped, `--feather` to soften
or harden the layer edges.
