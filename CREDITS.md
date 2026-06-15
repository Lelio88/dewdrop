# Credits & third-party assets

## Sounds

### Notification sound — `android/app/src/main/res/raw/drop.wav`

- **"Water Drop Sound High"** by **Mike Koenig** — via [SoundBible](https://soundbible.com/) (sound id `1232`).
- **License:** Creative Commons Attribution 3.0 ([CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)).
- **Attribution (must be surfaced to users, e.g. an in-app "À propos / Crédits" screen):**
  > Son de notification : « Water Drop Sound High » par Mike Koenig (soundbible.com), sous licence CC BY 3.0.
- **Processing (reproducible):** downloaded WAV, then trimmed + normalised to a short notification cue:
  ```bash
  curl -L "http://soundbible.com/grab.php?id=1232&type=wav" -o source.wav
  ffmpeg -i source.wav -af \
    "silenceremove=start_periods=1:start_duration=0.01:start_threshold=-45dB,\
     atrim=0:1.4,afade=t=out:st=1.15:d=0.25,loudnorm=I=-15:TP=-1.0,\
     aformat=channel_layouts=mono:sample_rates=44100" \
    android/app/src/main/res/raw/drop.wav
  ```

### Ambient soundscapes — `assets/audio/<environment>.ogg`

Per-decor looping ambiences. All sources are **CC0 1.0** (Public Domain, no
attribution required); listed here for transparency. Each was trimmed,
loudness-normalised and crossfade-looped (seamless) with ffmpeg.

| Decor | Source | Origin (OpenGameArt, CC0) |
|---|---|---|
| space | "Background space track" (MyVeryOwnDeadShip) | opengameart.org/content/background-space-track |
| underwater | "Underwater Theme II" | opengameart.org/content/underwater-theme-ii |
| forest | "CC0 Background Ambience" (Forest Ambience) | opengameart.org/content/cc0-background-ambience |
| beach | "Beach Ocean Waves" (jasinski) | opengameart.org/content/beach-ocean-waves |
| library | "Fireplace Sound loop" | opengameart.org/content/fireplace-sound-loop |
| mountain / desert | "wind whoosh loop" | opengameart.org/content/wind-whoosh-loop |

> TODO before public release: add an in-app credits line so the CC BY attribution
> (notification sound) is shown to end users (a repo file alone is not sufficient
> for CC BY). The CC0 ambiences above need no attribution.
