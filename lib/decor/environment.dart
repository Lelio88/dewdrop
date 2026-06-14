import 'package:dewdrop/decor/forest_decor.dart';
import 'package:dewdrop/decor/photo_decor.dart';
import 'package:dewdrop/decor/space_decor.dart';
import 'package:dewdrop/decor/themed_decor.dart';
import 'package:dewdrop/decor/underwater_decor.dart';
import 'package:flutter/material.dart';

/// Global rendering style for a decor.
enum RenderMode { drawn, photo }

/// How finished an environment's renderer is.
enum DecorStatus {
  /// Bespoke immersive renderer.
  full,

  /// On-theme placeholder ("ébauche") via [ThemedDecor].
  draft,
}

/// The DewDrop ambiances. Each has 2–3 variants.
enum Environment {
  space('Espace', Icons.public, ['Cosmos', 'Nuit noire', 'Planètes'],
      DecorStatus.full),
  underwater('Sous l’eau', Icons.water, ['Fonds marins', 'Poissons'],
      DecorStatus.full),
  forest('Forêt', Icons.forest, ['Chênes', 'Sakura', 'Canopée'],
      DecorStatus.full),
  beach('Plage', Icons.beach_access, ['Jour', 'Coucher'], DecorStatus.draft),
  library('Bibliothèque', Icons.menu_book, ['Cosy', 'Ancienne'],
      DecorStatus.draft),
  mountain('Montagne', Icons.landscape, ['Aube', 'Nuit'], DecorStatus.draft),
  desert('Désert', Icons.nights_stay, ['Dunes', 'Étoilé'], DecorStatus.draft);

  const Environment(this.label, this.icon, this.variants, this.status);

  final String label;
  final IconData icon;
  final List<String> variants;
  final DecorStatus status;

  int get variantCount => variants.length;
}

/// Builds the decor widget for [env] + [variant] in render [mode], floating
/// [child] over it.
Widget buildDecor(
  Environment env,
  int variant,
  RenderMode mode, {
  Widget? child,
}) {
  final v = variant.clamp(0, env.variantCount - 1);
  if (mode == RenderMode.photo) {
    return PhotoDecor(environment: env, variant: v, child: child);
  }
  return switch (env) {
    Environment.space =>
      SpaceDecor(variant: SpaceVariant.values[v], child: child),
    Environment.underwater => UnderwaterDecor(variant: v, child: child),
    Environment.forest => ForestDecor(variant: v, child: child),
    _ => ThemedDecor(palette: _palette(env, v), child: child),
  };
}

ThemedPalette _palette(Environment env, int v) => switch ((env, v)) {
      (Environment.forest, 0) => const ThemedPalette(
          top: Color(0xFF2E4A2E),
          bottom: Color(0xFF0C1A10),
          mote: Color(0x66BFE0A0),
          accent: Color(0xFFBFE0A0),
          moteCount: 55,
          drift: true,
        ),
      (Environment.forest, _) => const ThemedPalette(
          top: Color(0xFF7A4A66),
          bottom: Color(0xFF241420),
          mote: Color(0x99FFC2DC),
          accent: Color(0xFFFFC2DC),
          moteCount: 70,
          drift: true,
        ),
      (Environment.beach, 0) => const ThemedPalette(
          top: Color(0xFF7EC8E3),
          bottom: Color(0xFFE3C48E),
          mote: Color(0x44FFFFFF),
          accent: Color(0xFFFFFFFF),
          moteCount: 26,
          drift: true,
        ),
      (Environment.beach, _) => const ThemedPalette(
          top: Color(0xFFE8896B),
          bottom: Color(0xFF3A2350),
          mote: Color(0x66FFD9A0),
          accent: Color(0xFFFFD9A0),
          moteCount: 26,
          drift: true,
        ),
      (Environment.library, 0) => const ThemedPalette(
          top: Color(0xFF3A2A1E),
          bottom: Color(0xFF140D08),
          mote: Color(0x55FFE0A8),
          accent: Color(0xFFFFD090),
          moteCount: 45,
          drift: true,
        ),
      (Environment.library, _) => const ThemedPalette(
          top: Color(0xFF2A2018),
          bottom: Color(0xFF0E0A06),
          mote: Color(0x44FFD090),
          accent: Color(0xFFE0B070),
          moteCount: 38,
          drift: true,
        ),
      (Environment.mountain, 0) => const ThemedPalette(
          top: Color(0xFFE5A6A0),
          bottom: Color(0xFF243A52),
          mote: Color(0x44FFFFFF),
          accent: Color(0xFFFFFFFF),
          moteCount: 24,
          drift: true,
        ),
      (Environment.mountain, _) => const ThemedPalette(
          top: Color(0xFF0E1A34),
          bottom: Color(0xFF05070F),
          mote: Color(0x99EAF2FF),
          accent: Color(0xFFEAF2FF),
          moteCount: 120,
          drift: false,
        ),
      (Environment.desert, 0) => const ThemedPalette(
          top: Color(0xFF2A2440),
          bottom: Color(0xFF1A1208),
          mote: Color(0x55FFE0B0),
          accent: Color(0xFFFFE0B0),
          moteCount: 30,
          drift: true,
        ),
      (Environment.desert, _) => const ThemedPalette(
          top: Color(0xFF101830),
          bottom: Color(0xFF0A0A12),
          mote: Color(0x99EAF2FF),
          accent: Color(0xFFEAF2FF),
          moteCount: 140,
          drift: false,
        ),
      _ => const ThemedPalette(
          top: Color(0xFF1A1A2A),
          bottom: Color(0xFF0A0A12),
          mote: Color(0x66FFFFFF),
          accent: Color(0xFFFFFFFF),
          moteCount: 40,
          drift: true,
        ),
    };
