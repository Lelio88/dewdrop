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
