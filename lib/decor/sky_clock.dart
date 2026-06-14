/// Maps a wall-clock [time] to a daylight factor in `[0, 1]`.
///
/// `0` = deep night (stars fully visible), `1` = midday. Smooth ramps at
/// dawn (5h→8h) and dusk (18h→21h) so the sky transitions gently instead
/// of snapping between night and day.
double daylightFactor(DateTime time) {
  final hours = time.hour + time.minute / 60.0 + time.second / 3600.0;

  const dawnStart = 5.0;
  const dawnEnd = 8.0;
  const duskStart = 18.0;
  const duskEnd = 21.0;

  if (hours <= dawnStart || hours >= duskEnd) return 0.0;
  if (hours >= dawnEnd && hours <= duskStart) return 1.0;
  if (hours < dawnEnd) return _smoothstep(dawnStart, dawnEnd, hours);
  return 1.0 - _smoothstep(duskStart, duskEnd, hours);
}

double _smoothstep(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}
