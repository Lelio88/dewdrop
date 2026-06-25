import 'package:dewdrop/decor/environment.dart';

/// Parses a stored decor string `"<environment>:<variant>"` (e.g. `forest:1`)
/// into its [Environment] + variant index. Falls back to space/0.
(Environment, int) parseDecor(String value) {
  final parts = value.split(':');
  final env = Environment.values.firstWhere(
    (e) => e.name == parts.first,
    orElse: () => Environment.space,
  );
  final variant = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  return (env, variant);
}

/// Builds the stored decor string for an [env] + [variant].
String encodeDecor(Environment env, int variant) => '${env.name}:$variant';

RenderMode parseRenderMode(String value) =>
    value == 'drawn' ? RenderMode.drawn : RenderMode.photo;

/// A *favourite* decor snapshot — the encode/decode for a STARRED variant. It
/// captures the full look `"<environment>:<variant>:<render_mode>"`
/// (e.g. `forest:1:photo`), unlike [encodeDecor] which omits the mode: a
/// favourite must restore the exact preview, dessin/photo included, so the
/// home-screen swipe lands on precisely what was starred.
String encodeFavorite(Environment env, int variant, RenderMode mode) =>
    '${env.name}:$variant:${mode.name}';

/// Parses a favourite snapshot back into (env, variant, mode). Falls back
/// gracefully — unknown env → space, missing/bad variant → 0, missing/bad
/// mode → photo (reuses [parseDecor] + [parseRenderMode], so a plain
/// `"env:variant"` string is still valid and yields the photo mode).
(Environment, int, RenderMode) parseFavorite(String value) {
  final (env, variant) = parseDecor(value);
  final parts = value.split(':');
  final mode = parts.length > 2 ? parseRenderMode(parts[2]) : RenderMode.photo;
  return (env, variant, mode);
}
