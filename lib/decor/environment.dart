import 'package:dewdrop/decor/april_decor.dart';
import 'package:dewdrop/decor/aurora_decor.dart';
import 'package:dewdrop/decor/beach_decor.dart';
import 'package:dewdrop/decor/christmas_decor.dart';
import 'package:dewdrop/decor/desert_decor.dart';
import 'package:dewdrop/decor/fields_decor.dart';
import 'package:dewdrop/decor/forest_decor.dart';
import 'package:dewdrop/decor/halloween_decor.dart';
import 'package:dewdrop/decor/library_decor.dart';
import 'package:dewdrop/decor/mountain_decor.dart';
import 'package:dewdrop/decor/reception_signal.dart';
import 'package:dewdrop/decor/space_decor.dart';
import 'package:dewdrop/decor/underwater_decor.dart';
import 'package:flutter/material.dart';

/// Global rendering style for a decor.
enum RenderMode { drawn, photo }

/// The DewDrop ambiances. Each has 2–3 variants.
enum Environment {
  space('Espace', Icons.public, ['Cosmos', 'Nuit noire', 'Planètes']),
  underwater('Sous l’eau', Icons.water, ['Fonds marins', 'Poissons']),
  forest('Forêt', Icons.forest, ['Chênes', 'Sakura', 'Canopée']),
  beach('Plage', Icons.beach_access, ['Jour', 'Coucher']),
  library('Bibliothèque', Icons.menu_book, ['Cosy', 'Ancienne']),
  mountain('Montagne', Icons.landscape, ['Aube', 'Nuit']),
  desert('Désert', Icons.nights_stay, ['Dunes', 'Étoilé']),
  aurora('Aurores boréales', Icons.ac_unit, ['Émeraude', 'Magenta']),
  fields('Champs', Icons.grass, ['Prairie', 'Blé']),
  // Seasonal "marronnier" worlds — hidden from the normal univers picker (see
  // [seasonal]); shown only when their date window forces them onto the home.
  // Single scene each: the lock leaves nothing to switch between.
  christmas('Noël', Icons.celebration, ['Scène'], seasonal: true),
  halloween('Halloween', Icons.nightlight_round, ['Scène'], seasonal: true),
  april('1er avril', Icons.construction, ['Scène'], seasonal: true);

  const Environment(
    this.label,
    this.icon,
    this.variants, {
    this.seasonal = false,
  });

  final String label;
  final IconData icon;
  final List<String> variants;

  /// A date-gated marronnier world (Noël / Halloween / 1er avril). Excluded from
  /// the normal univers picker; only ever shown through the seasonal lock on the
  /// home screen.
  final bool seasonal;

  int get variantCount => variants.length;
}

/// Builds the decor widget for [env] + [variant] in render [mode], floating
/// [child] over it. When [reception] is provided, the decor plays an amplified
/// burst each time it pulses (a pensée was received).
Widget buildDecor(
  Environment env,
  int variant,
  RenderMode mode, {
  Widget? child,
  ReceptionSignal? reception,
  bool parallax = true,
}) {
  final v = variant.clamp(0, env.variantCount - 1);
  final assetRoot = mode == RenderMode.photo ? 'photo' : 'illustrated';

  // Every decor runs through the unified pipeline: a parallax [DecorBackdrop]
  // from the 'photo' or 'illustrated' asset tree (the same scene either way),
  // with the decor's bespoke animated FX layered on top.
  //
  // Clip to the decor's own bounds: the backdrop deliberately OVER-draws ~6%
  // past its edges (warp `_overscale` / legacy layer scale 1.12) so a tilt never
  // reveals a gap. Un-clipped, that overspill bleeds into whatever sits beside
  // it — a neighbouring page in the world picker's PageView, or the outgoing
  // world during the home slide — leaving a thin strip of the wrong world. The
  // clip confines each decor to its slot without touching the gap-free coverage.
  final decor = switch (env) {
    Environment.space => SpaceDecor(
      variant: SpaceVariant.values[v],
      assetRoot: assetRoot,
      reception: reception,
      parallax: parallax,
      child: child,
    ),
    Environment.underwater => UnderwaterDecor(
      variant: v,
      assetRoot: assetRoot,
      reception: reception,
      parallax: parallax,
      child: child,
    ),
    Environment.forest => ForestDecor(
      variant: v,
      assetRoot: assetRoot,
      reception: reception,
      child: child,
    ),
    Environment.beach => BeachDecor(
      variant: v,
      assetRoot: assetRoot,
      reception: reception,
      child: child,
    ),
    Environment.library => LibraryDecor(
      variant: v,
      assetRoot: assetRoot,
      reception: reception,
      child: child,
    ),
    Environment.mountain => MountainDecor(
      variant: v,
      assetRoot: assetRoot,
      reception: reception,
      child: child,
    ),
    Environment.desert => DesertDecor(
      variant: v,
      assetRoot: assetRoot,
      reception: reception,
      child: child,
    ),
    Environment.aurora => AuroraDecor(
      variant: v,
      assetRoot: assetRoot,
      reception: reception,
      child: child,
    ),
    Environment.fields => FieldsDecor(
      variant: v,
      assetRoot: assetRoot,
      reception: reception,
      child: child,
    ),
    Environment.christmas => ChristmasDecor(
      variant: v,
      assetRoot: assetRoot,
      reception: reception,
      child: child,
    ),
    Environment.halloween => HalloweenDecor(
      variant: v,
      assetRoot: assetRoot,
      reception: reception,
      child: child,
    ),
    Environment.april => AprilDecor(
      variant: v,
      assetRoot: assetRoot,
      reception: reception,
      child: child,
    ),
  };
  return ClipRect(child: decor);
}
