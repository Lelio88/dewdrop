# Credits & third-party assets

## Notification sound — `android/app/src/main/res/raw/drop.wav`

- **"Water Drop Sound High"** by **Mike Koenig** — via [SoundBible](https://soundbible.com/) (sound id `1232`).
- **License:** Creative Commons Attribution 3.0 ([CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)).
- **Attribution (must be surfaced to users, e.g. an in-app "À propos / Crédits" screen):**
  > Son de notification : « Water Drop Sound High » par Mike Koenig (soundbible.com), sous licence CC BY 3.0.
- **Processing (reproducible):**
  ```bash
  curl -L "http://soundbible.com/grab.php?id=1232&type=wav" -o source.wav
  ffmpeg -i source.wav -af \
    "silenceremove=start_periods=1:start_duration=0.01:start_threshold=-45dB,\
     atrim=0:1.4,afade=t=out:st=1.15:d=0.25,loudnorm=I=-15:TP=-1.0,\
     aformat=channel_layouts=mono:sample_rates=44100" \
    android/app/src/main/res/raw/drop.wav
  ```

## Decor soundscapes — `assets/audio/`

Each decor has **two layers** — a looping **ambiance** bed (`*_amb.ogg`) and a
looping **music** track (`*_mus.ogg`) — plus occasional **one-shots**
(`oneshot/*.ogg`: whale calls, thunder, tumbleweed, ice cracks, page turns,
purrs, pigeon…). All loops are loudness-normalised by group (music ≈ -18 LUFS,
ambiance ≈ -28 LUFS) and crossfade-looped (seamless) with ffmpeg.

Sourcing policy: **CC0 1.0 / Public Domain preferred** (no attribution
required). The humpback-whale bank (underwater one-shots) is a **public-domain**
NOAA recording, segmented from the Internet Archive. The music tracks below were
sourced from **Freesound under CC0** (listed for transparency, not obligation):

| Decor | Music | Freesound id |
|---|---|---|
| Forêt | acoustic (slowed 0.75×) | 261608 |
| Plage | vibraphone (slowed 0.75×) | 238908 |
| Bibliothèque | jazz piano (slowed 0.8×) | 770969 |
| Montagne | harp | 503244 |
| Désert | duduk | 352572 |
| Aurore | glacial pad / dreamy pad (2 variants, random) | 695587 · 360352 |
| Espace · Sous-l'eau | (sourced earlier — CC0) | — |

Aurora ambiance components (Freesound, CC0): polar wind `607839`; ice cracks
`177225` · `549014` · `733814`; crystalline shimmer `460416`. Beach ambiance
adds a CC0 tropical layer (`268962`) over the waves.

> The remaining ambiance beds and one-shots (fire, wind, water, cowbells,
> pigeon, dune, page turns, cat purrs, thunder) are CC0 / Public Domain from
> Freesound and OpenGameArt — no attribution required.

## ⚠️ To finalize before a public release

1. **Surface the CC BY notification-sound attribution in-app** (an "À propos /
   Crédits" screen) — a repo file alone is not sufficient for CC BY.
2. **Desert tumbleweed** (`assets/audio/oneshot/desert_tumble_*.ogg`) may be
   **CC BY** — confirm the original author and add the attribution here, **or**
   swap it for a CC0 take so no attribution is owed.
