import 'package:dewdrop/decor/aurora_decor.dart';
import 'package:dewdrop/decor/beach_decor.dart';
import 'package:dewdrop/decor/desert_decor.dart';
import 'package:dewdrop/decor/forest_decor.dart';
import 'package:dewdrop/decor/library_decor.dart';
import 'package:dewdrop/decor/mountain_decor.dart';
import 'package:dewdrop/decor/photo_decor.dart';
import 'package:dewdrop/decor/space_decor.dart';
import 'package:dewdrop/decor/underwater_decor.dart';
import 'package:flutter/material.dart';

/// Global rendering style for a decor.
enum RenderMode { drawn, photo }

/// How finished an environment's renderer is.
enum DecorStatus {
  /// Bespoke immersive renderer.
  full,

  /// On-theme placeholder ("ébauche") — not yet a bespoke scene.
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
  beach('Plage', Icons.beach_access, ['Jour', 'Coucher'], DecorStatus.full),
  library('Bibliothèque', Icons.menu_book, ['Cosy', 'Ancienne'],
      DecorStatus.full),
  mountain('Montagne', Icons.landscape, ['Aube', 'Nuit'], DecorStatus.full),
  desert('Désert', Icons.nights_stay, ['Dunes', 'Étoilé'], DecorStatus.full),
  aurora('Aurores boréales', Icons.ac_unit, ['Émeraude', 'Magenta'],
      DecorStatus.full);

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
    Environment.beach => BeachDecor(variant: v, child: child),
    Environment.library => LibraryDecor(variant: v, child: child),
    Environment.mountain => MountainDecor(variant: v, child: child),
    Environment.desert => DesertDecor(variant: v, child: child),
    Environment.aurora => AuroraDecor(variant: v, child: child),
  };
}
