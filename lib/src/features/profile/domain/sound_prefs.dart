/// Per-decor soundscape customization (mirrors `profiles.sound_prefs`).
///
/// Stored as JSON keyed by [Environment.name]. Only values the user explicitly
/// changed are kept; anything absent falls back to the engine's per-category
/// defaults (so the JSON stays small and new decors/categories work without a
/// migration). `vol` and `freq` are 0..1.
///
/// Shape:
/// ```json
/// { "desert": { "amb": {"on": true, "vol": 1.0},
///               "mus": {"on": true, "vol": 1.0},
///               "sec": { "thunder": {"on": true, "vol": 0.6, "freq": 0.5} } } }
/// ```
library;

/// On/off + volume for a main layer (ambiance or music).
class LayerPref {
  const LayerPref({this.on = true, this.vol = 1.0});

  final bool on;
  final double vol;

  LayerPref copyWith({bool? on, double? vol}) =>
      LayerPref(on: on ?? this.on, vol: vol ?? this.vol);

  Map<String, dynamic> toJson() => {'on': on, 'vol': vol};

  factory LayerPref.fromJson(Map<String, dynamic>? m) => m == null
      ? const LayerPref()
      : LayerPref(
          on: m['on'] as bool? ?? true,
          vol: (m['vol'] as num?)?.toDouble() ?? 1.0,
        );
}

/// On/off + volume + frequency for a secondary (one-shot) category.
/// [freq] 0..1 scales the firing interval (0.5 = engine default, 1 = often).
class SecondaryPref {
  const SecondaryPref({this.on = true, this.vol = 0.5, this.freq = 0.5});

  final bool on;
  final double vol;
  final double freq;

  SecondaryPref copyWith({bool? on, double? vol, double? freq}) =>
      SecondaryPref(
        on: on ?? this.on,
        vol: vol ?? this.vol,
        freq: freq ?? this.freq,
      );

  Map<String, dynamic> toJson() => {'on': on, 'vol': vol, 'freq': freq};

  factory SecondaryPref.fromJson(
    Map<String, dynamic>? m, {
    double defVol = 0.5,
  }) => m == null
      ? SecondaryPref(vol: defVol)
      : SecondaryPref(
          on: m['on'] as bool? ?? true,
          vol: (m['vol'] as num?)?.toDouble() ?? defVol,
          freq: (m['freq'] as num?)?.toDouble() ?? 0.5,
        );
}

/// The soundscape prefs for one environment.
class EnvSoundPref {
  const EnvSoundPref({
    this.amb = const LayerPref(),
    this.mus = const LayerPref(),
    this.sec = const {},
  });

  final LayerPref amb;
  final LayerPref mus;
  final Map<String, SecondaryPref> sec;

  EnvSoundPref copyWith({
    LayerPref? amb,
    LayerPref? mus,
    Map<String, SecondaryPref>? sec,
  }) => EnvSoundPref(
    amb: amb ?? this.amb,
    mus: mus ?? this.mus,
    sec: sec ?? this.sec,
  );

  /// Returns a copy with secondary [key] replaced by [pref].
  EnvSoundPref withSecondary(String key, SecondaryPref pref) =>
      copyWith(sec: {...sec, key: pref});

  Map<String, dynamic> toJson() => {
    'amb': amb.toJson(),
    'mus': mus.toJson(),
    if (sec.isNotEmpty) 'sec': sec.map((k, v) => MapEntry(k, v.toJson())),
  };

  factory EnvSoundPref.fromJson(Map<String, dynamic> m) => EnvSoundPref(
    amb: LayerPref.fromJson((m['amb'] as Map?)?.cast<String, dynamic>()),
    mus: LayerPref.fromJson((m['mus'] as Map?)?.cast<String, dynamic>()),
    sec: ((m['sec'] as Map?)?.cast<String, dynamic>() ?? const {}).map(
      (k, v) => MapEntry(
        k,
        SecondaryPref.fromJson((v as Map?)?.cast<String, dynamic>()),
      ),
    ),
  );
}

/// All per-decor soundscape prefs.
class SoundPrefs {
  const SoundPrefs(this.byEnv);

  final Map<String, EnvSoundPref> byEnv;

  static const empty = SoundPrefs({});

  /// Prefs for [env], or sensible defaults when the user hasn't customized it.
  EnvSoundPref forEnv(String env) => byEnv[env] ?? const EnvSoundPref();

  SoundPrefs withEnv(String env, EnvSoundPref pref) =>
      SoundPrefs({...byEnv, env: pref});

  Map<String, dynamic> toJson() => byEnv.map((k, v) => MapEntry(k, v.toJson()));

  factory SoundPrefs.fromJson(Map<String, dynamic>? m) => m == null
      ? empty
      : SoundPrefs(
          m.map(
            (k, v) => MapEntry(
              k,
              EnvSoundPref.fromJson((v as Map).cast<String, dynamic>()),
            ),
          ),
        );
}
