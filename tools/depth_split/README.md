# depth_split — assets de décor (warp de profondeur)

Transforme une source photo (`_src/<env>/<v>/Base.png`) en **paire de warp de
profondeur** — `full.webp` (l'image entière) + `depth.webp` (carte de profondeur
grayscale) — consommée par le moteur de décors Flutter (`lib/decor/decor_backdrop.dart`).

Le rendu déforme l'image entière en maillage `drawVertices` (chaque sommet décalé
de `profondeur × tilt`) : aucune découpe, donc **aucun trou à inpainter**, donc aucun
halo / fantôme. C'est ce qui a remplacé le découpage en couches (cf. `## Legacy`).

## Setup (une fois)

```powershell
cd tools/depth_split
python -m venv .venv
.venv\Scripts\python -m pip install --upgrade pip
# CPU :  .venv\Scripts\python -m pip install torch --index-url https://download.pytorch.org/whl/cpu
# GPU NVIDIA (bien plus rapide) :
#        .venv\Scripts\python -m pip install torch --index-url https://download.pytorch.org/whl/cu128
.venv\Scripts\python -m pip install -r requirements.txt
# Filigrane uniquement (clean_watermark.py) — pas requis pour le warp :
.venv\Scripts\python -m pip install simple-lama-inpainting --no-deps
```

## Pipeline

Depuis la **racine du repo** :

```powershell
# (optionnel) retirer le filigrane Gemini des sources, AVANT tout le reste
tools\depth_split\.venv\Scripts\python tools\depth_split\clean_watermark.py
# (mode dessin) styliser chaque source en aquarelle -> illus.png
tools\depth_split\.venv\Scripts\python tools\depth_split\illustrate_all.py
# générer les paires de warp pour TOUTES les scènes (photo + dessin)
tools\depth_split\.venv\Scripts\python tools\depth_split\warp_batch.py
#   -> assets/{photo,illustrated}/<env>/<v>/{full.webp,depth.webp}
```

`warp_assets.py` traite **une** scène (`python warp_assets.py <src_image> <out_dir>`) ;
`warp_batch.py` boucle sur toutes les scènes en réutilisant le modèle de profondeur.

Profondeur via **Depth Anything V2 Large** (chargée une fois par
`split_layers.build_pipe()`, réutilisée par `warp_assets` / `warp_batch`).

## Legacy

`split_layers.py` est l'**ancien** pipeline : découpe en couches (`0.png` =
le plus loin … `N-1.png` = le plus proche) + inpaint des trous derrière le
premier plan. Abandonné au profit du warp, mais **conservé** car il héberge le
chargeur du modèle de profondeur (`build_pipe`/`_free`) et les helpers LaMa
(`build_lama` / `_lama_inpaint`) encore utilisés par `clean_watermark.py`.
Ne plus s'en servir pour générer des assets.
