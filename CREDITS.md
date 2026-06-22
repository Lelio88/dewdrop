# Credits & third-party assets

## Notification sound — `android/app/src/main/res/raw/drop.wav`

- **"Water_drop_9.wav"** — [Freesound #166325](https://freesound.org/s/166325/).
- **License:** Creative Commons 0 ([CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/))
  — public domain, **no attribution required**.
- **Channel:** changing this sound requires bumping `thoughtsChannelId`
  (currently `thoughts_v3`) **and** the matching ids in `AndroidManifest.xml`
  (`default_notification_channel_id`) and `supabase/functions/send-thought-push`
  (`channel_id`) — an Android channel's sound is immutable once created.
- **Processing (reproducible):**
  ```bash
  # source: Freesound 166325 preview (CC0)
  ffmpeg -i 166325.mp3 -af \
    "silenceremove=start_periods=1:start_duration=0.005:start_threshold=-50dB,\
     atrim=0:0.9,afade=t=out:st=0.7:d=0.2,loudnorm=I=-15:TP=-1.0,\
     aformat=channel_layouts=mono:sample_rates=44100" tmp.wav
  ffmpeg -i tmp.wav -c:a pcm_s16le -ar 44100 -ac 1 \
    android/app/src/main/res/raw/drop.wav
  ```

## Écran de chargement — `assets/audio/oneshot/`

- **`dewdrop_jingle.mp3`** — jingle 8-bit « harmonisé » **synthétisé par nous**
  (réplique du mockup, script `tools/sounds/gen_loader_audio.py` → carrées
  band-limitées + 2ᵉ voix d'harmonie + basse triangle + réverb de Schroeder) :
  **œuvre originale, aucune attribution requise**.
- **`water_drop.wav`** — le « ploc » de la goutte. **Copie conforme du `drop.wav`
  de notification** (Freesound [#166325](https://freesound.org/s/166325/), **CC0
  1.0** — domaine public, aucune attribution requise ; voir la 1ʳᵉ section). Un
  premier SFX issu de YouTube avait été écarté faute de licence claire pour un
  repo public ; le volume du loader (`_kDropVolume = 0.70`) a été calé en A/B
  pour reproduire le niveau perçu qui avait été validé avec cet ancien son.

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
| Champs | warm acoustic guitar | CC0 (Freesound, forest batch — never used by any other decor) |
| Espace · Sous-l'eau | (sourced earlier — CC0) | — |

Aurora ambiance components (Freesound, CC0): polar wind `607839`; ice cracks
`177225` · `549014` · `733814`; crystalline shimmer `460416`. Beach ambiance
adds a CC0 tropical layer (`268962`) over the waves. **Fields (Champs)** ambiance
= *Wheat in the Wind* (**Freesound #240914** by **bdvictor** — a real Kentucky
wheat field rustling in a gentle breeze, mic at the base of the stalks); the bee
one-shots (`fields_bee_1/2`) = *Bumblebee #1 / #2* (**BigSoundBank #1000 / #1001**
by **Joseph SARDIN**, a bumblebee looking for a flower). All **CC0 1.0** — public
domain, no attribution required (listed for transparency).

> The remaining ambiance beds and one-shots (fire, wind, water, cowbells,
> pigeon, dune, page turns, cat purrs, thunder) are CC0 / Public Domain from
> Freesound and OpenGameArt — no attribution required.

## ⚠️ To finalize before a public release

1. **Desert tumbleweed** (`assets/audio/oneshot/desert_tumble_*.ogg`) is
   **CC BY 4.0** — built from Freesound [#204028](https://freesound.org/s/204028/)
   + [#204031](https://freesound.org/s/204031/) ("Tumbleweed_Impact" by
   **duckduckpony**). **✅ Resolved** — the attribution is surfaced **in-app** in
   the « À propos & crédits » screen (`about_screen.dart`, guarded by
   `about_screen_test.dart`), which satisfies CC BY's visible-credit requirement.
   (Alternative, if we ever want to drop the visible credit: rebuild the one-shots
   from the CC0 takes already downloaded — `tools/sounds/tumble/T1.mp3` =
   Freesound #666249, `T4.mp3` = #667738, both CC0 — so no attribution is owed.)
2. **Champs music** (`assets/audio/fields_mus.ogg` = `forest_mus/MF4_warmgtr.mp3`,
   from the CC0 forest batch, never used by another decor) — its exact Freesound
   id was not recorded; backfill it here for transparency (CC0 → no attribution
   owed regardless).
