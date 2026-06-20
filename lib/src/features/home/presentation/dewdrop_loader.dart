import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

/// Écran de chargement signature de DewDrop : une goutte de rosée tombe sur une
/// feuille, y glisse, se détache et tombe dans l'eau (onde), pendant que le nom
/// « DewDrop » apparaît. Style « inner peace » (Kung Fu Panda 2).
///
/// Portage fidèle du mockup `tools/mockups/dewdrop_loader.html` (validé) :
///  - tige + 2 feuilles + berge de mousse + plan d'eau,
///  - goutte qui se pose au milieu de la feuille puis glisse (easing sinus),
///  - VFX : rebond élastique de la feuille, reflet mobile sur la goutte, rayon
///    de lumière qui éclaire la plante, éclat d'étoiles 8-bit sur le nom,
///  - son : « ploc » d'eau pile au contact + jingle 8-bit harmonisé sur le nom.
///
/// Rendu Canvas pur (cohérent avec le moteur de décors). L'animation tourne en
/// boucle ; l'hôte ([HomeGate]) la masque dès que le profil est prêt (et après
/// une durée minimale pour qu'on la voie en entier). Un tap saute l'attente.
class DewDropLoader extends StatefulWidget {
  const DewDropLoader({
    super.key,
    this.onTap,
    this.playSound = true,
    this.dropVolume = _kDropVolume,
    this.jingleVolume = _kJingleVolume,
  });

  /// Appelé quand l'utilisateur tape l'écran (pour sauter l'attente).
  final VoidCallback? onTap;

  /// Joue le ploc + le jingle une fois au démarrage.
  final bool playSound;

  /// Volumes (0..1) — exposés pour le réglage à l'oreille (dev_loader_preview).
  final double dropVolume;
  final double jingleVolume;

  @override
  State<DewDropLoader> createState() => _DewDropLoaderState();
}

// Volumes calés à l'oreille. Jingle : réglé sur l'émulateur. Goutte : le fichier
// est le drop.wav CC0 (cf. CREDITS.md) et 0.70 reproduit le niveau perçu de
// l'ancien SFX que l'utilisateur avait calé à 0.50 — A/B de loudness, les deux
// fichiers n'ayant pas la même intensité de base (CC0 plus transitoire).
const double _kJingleVolume = 0.75;
const double _kDropVolume = 0.70;

class _DewDropLoaderState extends State<DewDropLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  AudioPlayer? _dropPlayer;
  AudioPlayer? _jinglePlayer;
  Timer? _dropTimer;
  Timer? _jingleTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: 2200,
      ), // cycle = ARC 1.2s + hold 1.0s
    )..repeat();
    if (widget.playSound) _scheduleSound();
  }

  void _scheduleSound() {
    _dropPlayer = AudioPlayer()..setVolume(widget.dropVolume);
    _jinglePlayer = AudioPlayer()..setVolume(widget.jingleVolume);
    // Jingle dès l'apparition du nom (ARC * 0.5 = 0.6 s) ; ploc au contact avec
    // l'eau (fallEnd * ARC ≈ 1.14 s). Joués UNE fois (pas à chaque boucle).
    _jingleTimer = Timer(const Duration(milliseconds: 600), () {
      _jinglePlayer?.play(AssetSource('audio/oneshot/dewdrop_jingle.mp3'));
    });
    _dropTimer = Timer(const Duration(milliseconds: 1140), () {
      _dropPlayer?.play(AssetSource('audio/oneshot/water_drop.wav'));
    });
  }

  @override
  void dispose() {
    _dropTimer?.cancel();
    _jingleTimer?.cancel();
    _ctrl.dispose();
    _dropPlayer?.dispose();
    _jinglePlayer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: ColoredBox(
        color: const Color(0xFF050F16),
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _LoaderPainter(_ctrl),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

// ── helpers maths ────────────────────────────────────────────────────────────
double _lerp(double a, double b, double t) => a + (b - a) * t;
double _clamp01(double x) => x < 0 ? 0 : (x > 1 ? 1 : x);
double _easeInQuad(double t) => t * t;
double _easeOutQuad(double t) => 1 - (1 - t) * (1 - t);
double _easeInOutSine(double t) => 0.5 * (1 - math.cos(math.pi * t));

class _P {
  const _P(this.x, this.y);
  final double x;
  final double y;
}

_P _cubic(_P p0, _P p1, _P p2, _P p3, double t) {
  final u = 1 - t,
      a = u * u * u,
      b = 3 * u * u * t,
      c = 3 * u * t * t,
      d = t * t * t;
  return _P(
    a * p0.x + b * p1.x + c * p2.x + d * p3.x,
    a * p0.y + b * p1.y + c * p2.y + d * p3.y,
  );
}

// ── géométrie de la plante (normalisée, comme le mockup) ─────────────────────
const _stemR = _P(0.40, 1.00);
const _stemC1 = _P(0.41, 0.72);
const _stemC2 = _P(0.31, 0.46);
const _stemA = _P(0.30, 0.25);
final _up = _cubic(
  _stemR,
  _stemC1,
  _stemC2,
  _stemA,
  0.74,
); // attache feuille haute
final _low = _cubic(
  _stemR,
  _stemC1,
  _stemC2,
  _stemA,
  0.40,
); // attache feuille basse

const double _wl = 0.86; // ligne d'eau
const double _impact = 0.92; // entrée de la goutte dans l'eau
const double _arc = 1.2;
const double _endHold = 1.0;
const double _cycle = _arc + _endHold;
// timeline de l'arc (fractions de l'arc)
const double _descEnd = 0.20, _rollEnd = 0.68, _hangEnd = 0.84, _fallEnd = 0.97;
const double _contactS = 0.42; // la goutte se pose au milieu de la feuille

class _Leaf {
  const _Leaf(this.b, this.c1, this.c2, this.tip);
  final _P b, c1, c2, tip;
}

_Leaf _mainLeaf(double dip) => _Leaf(
  _up,
  _P(_up.x + 0.16, _up.y - 0.005),
  _P(_up.x + 0.32, _up.y + 0.10 + 0.018 * dip),
  _P(_up.x + 0.42, _up.y + 0.22 + 0.022 * dip),
);

double _wMain(double s) =>
    0.058 * math.pow(math.sin(math.pi * s), 0.60).toDouble();
double _wLow(double s) =>
    0.046 * math.pow(math.sin(math.pi * s), 0.60).toDouble();

// mousse : brins précalculés (graine fixe -> stable, pas de scintillement)
class _Frond {
  _Frond(this.s, this.len, this.lean, this.shade);
  final double s, len, lean, shade;
}

final List<_Frond> _moss = () {
  final r = math.Random(7);
  final out = List.generate(
    82,
    (_) => _Frond(
      r.nextDouble(),
      0.009 + r.nextDouble() * 0.020,
      (r.nextDouble() - 0.5) * 0.6,
      r.nextDouble(),
    ),
  )..sort((a, b) => a.s.compareTo(b.s));
  return out;
}();

// éclat : positions des étoiles autour du mot
const List<List<double>> _spk = [
  [-0.17, -0.03],
  [0.17, -0.04],
  [-0.10, 0.05],
  [0.12, 0.06],
  [-0.02, -0.08],
  [0.06, 0.07],
];

class _LoaderPainter extends CustomPainter {
  _LoaderPainter(this.anim) : super(repaint: anim);
  final Animation<double> anim;

  late double W, H, S;
  Offset _px(_P p) => Offset(p.x * W, p.y * H);

  // feuille basse (controls calculés à partir de _low — pas const en Dart)
  _Leaf get _lowGeom => _Leaf(
    _low,
    _P(_low.x - 0.15, _low.y - 0.01),
    _P(_low.x - 0.30, _low.y + 0.01),
    _P(_low.x - 0.44, _low.y + 0.03),
  );

  @override
  void paint(Canvas canvas, Size size) {
    W = size.width;
    H = size.height;
    S = math.min(W, H);
    final local = anim.value * _cycle;
    final inArc = local < _arc;
    final p = _clamp01(local / _arc);

    _bg(canvas);
    _lightRay(canvas);

    // « poids » de la goutte -> fléchissement, puis rebond amorti dans le temps
    double dip = 0;
    if (p > _descEnd && p < _hangEnd) {
      dip = _easeOutQuad(_clamp01((p - _descEnd) / (_rollEnd - _descEnd)));
    } else if (p >= _hangEnd) {
      final bt = local - _hangEnd * _arc;
      dip = math.exp(-bt * 2.0) * math.cos(bt * math.pi * 2 * 1.9);
    }

    _drawStem(canvas);
    _water(canvas);
    _mound(canvas);
    _drawLeaf(canvas, _lowGeom, _wLow, const [
      Color(0xFF1F4634),
      Color(0xFF2A6045),
      Color(0xFF163A2C),
    ], 0.32);
    final g = _mainLeaf(dip);
    _drawLeaf(canvas, g, _wMain, const [
      Color(0xFF244E3B),
      Color(0xFF2F6E4E),
      Color(0xFF193F30),
    ], 0.5);
    _plantLight(canvas);

    final tipL = _P(
      _up.x + 0.42,
      _up.y + 0.242,
    ); // pointe à pleine charge (stable)
    final baseR = S * 0.030;
    if (inArc) {
      _P pos;
      double r = baseR, stretch = 1;
      final contact = _cubic(g.b, g.c1, g.c2, g.tip, _contactS);
      final top = _P(contact.x - 0.03, 0.04);
      if (p < _descEnd) {
        final u = p / _descEnd;
        pos = _P(
          _lerp(top.x, contact.x, _easeInQuad(u)),
          _lerp(top.y, contact.y, _easeInQuad(u)),
        );
        stretch = _lerp(1.35, 1.0, _easeOutQuad(u));
      } else if (p < _rollEnd) {
        final u = (p - _descEnd) / (_rollEnd - _descEnd);
        pos = _cubic(
          g.b,
          g.c1,
          g.c2,
          g.tip,
          _lerp(_contactS, 1.0, _easeInOutSine(u)),
        );
        pos = _P(pos.x, pos.y - 0.012);
        stretch = 1 + 0.05 * math.sin(math.pi * u);
      } else if (p < _hangEnd) {
        final e = _easeInOutSine((p - _rollEnd) / (_hangEnd - _rollEnd));
        pos = _P(tipL.x, tipL.y - 0.012 + 0.020 * e);
        r = baseR * (1 + 0.28 * e);
        stretch = 1 + 0.55 * e;
      } else if (p < _fallEnd) {
        final t = _easeInQuad((p - _hangEnd) / (_fallEnd - _hangEnd));
        pos = _P(_lerp(tipL.x, 0.68, t), _lerp(tipL.y + 0.006, _impact, t));
        stretch = _lerp(1.55, 1.15, t);
      } else {
        final t = (p - _fallEnd) / (1 - _fallEnd);
        pos = const _P(0.68, _impact);
        stretch = _lerp(1.15, 0.6, t);
        r = baseR * _lerp(1, 1.3, t);
      }
      _drawDrop(canvas, pos, r, stretch, p * 1.5);
    } else {
      final et = _clamp01((local - _arc) / _endHold);
      _waterImpact(canvas, 0.68, _impact, et);
    }

    // mot DewDrop + éclat de sparkles sur la note finale du jingle
    const fi0 = _arc * 0.50, fi1 = _arc * 0.92, fo0 = _cycle - 0.22;
    final wordA = local < fi0
        ? 0.0
        : local < fi1
        ? _clamp01((local - fi0) / (fi1 - fi0))
        : local < fo0
        ? 1.0
        : _clamp01(1 - (local - fo0) / 0.22);
    _wordmark(canvas, wordA);
    if (wordA > 0.2) _wordSparkle(canvas, local - (_arc * 0.5 + 0.85));
  }

  // ── fond + eau ─────────────────────────────────────────────────────────────
  void _bg(Canvas canvas) {
    final rect = Offset.zero & Size(W, H);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, H),
          const [Color(0xFF16333F), Color(0xFF0C2330), Color(0xFF050F16)],
          const [0.0, 0.45, 1.0],
        ),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(W / 2, H * 0.5),
          S * 0.95,
          const [Color(0x00000000), Color(0x8C000000)],
          const [0.0, 1.0],
        ),
    );
    for (var i = 0; i < 7; i++) {
      final x = (i * 0.137 + 0.1) % 1, y = (i * 0.21 + 0.05) % 0.7;
      final r = 0.01 + 0.02 * ((i * 7) % 5) / 5;
      final a = 0.015 + 0.02 * ((i * 3) % 4) / 4;
      canvas.drawCircle(
        Offset(x * W, y * H),
        r * S,
        Paint()..color = Color.fromRGBO(150, 210, 220, a),
      );
    }
  }

  void _water(Canvas canvas) {
    canvas.drawRect(
      Rect.fromLTRB(0, _wl * H, W, H),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, _wl * H), Offset(0, H), const [
          Color(0xFF0A2530),
          Color(0xFF04121A),
        ]),
    );
    canvas.drawLine(
      Offset(0, _wl * H),
      Offset(W, _wl * H),
      Paint()
        ..color = Color.fromRGBO(150, 210, 220, 0.16)
        ..strokeWidth = S * 0.0028,
    );
  }

  // rayon de lumière qui drape sur la plante (derrière)
  void _lightRay(Canvas canvas) {
    final path = Path()
      ..moveTo(W * 0.18, 0)
      ..lineTo(W * 0.40, 0)
      ..lineTo(W * 0.66, H * 0.70)
      ..lineTo(W * 0.14, H * 0.70)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.linear(Offset(0, 0), Offset(0, H * 0.70), const [
          Color(0x21D2F0FA),
          Color(0x00D2F0FA),
        ]),
    );
  }

  // halo additif qui éclaire la plante (par-dessus les feuilles)
  void _plantLight(Canvas canvas) {
    final c = Offset(W * 0.46, H * 0.40);
    canvas.drawCircle(
      c,
      S * 0.34,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(c, S * 0.34, const [
          Color(0x1FC3E8F2),
          Color(0x00C3E8F2),
        ]),
    );
  }

  // ── tige ─────────────────────────────────────────────────────────────────
  void _drawStem(Canvas canvas) {
    const n = 32;
    final c = List.generate(
      n + 1,
      (i) => _cubic(_stemR, _stemC1, _stemC2, _stemA, i / n),
    );
    double wAt(int i) {
      final t = i / n;
      return 0.013 * math.pow(1 - t, 3).toDouble() + 0.0085 * (1 - t) + 0.0022;
    }

    Offset normal(List<_P> pts, int i) {
      final a = pts[math.max(0, i - 1)],
          b = pts[math.min(pts.length - 1, i + 1)];
      var nx = -(b.y - a.y), ny = (b.x - a.x);
      final l = math.sqrt(nx * nx + ny * ny);
      if (l > 0) {
        nx /= l;
        ny /= l;
      }
      if (ny < 0) {
        nx = -nx;
        ny = -ny;
      }
      return Offset(nx, ny);
    }

    final path = Path();
    for (var i = 0; i <= n; i++) {
      final nrm = normal(c, i);
      final w = wAt(i);
      final p = _px(_P(c[i].x + nrm.dx * w, c[i].y + nrm.dy * w));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    for (var i = n; i >= 0; i--) {
      final nrm = normal(c, i);
      final w = wAt(i);
      final p = _px(_P(c[i].x - nrm.dx * w, c[i].y - nrm.dy * w));
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    final r = _px(_stemR), a = _px(_stemA);
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          r,
          a,
          const [Color(0xFF1D4632), Color(0xFF2C6346), Color(0xFF26583E)],
          const [0.0, 0.6, 1.0],
        ),
    );
  }

  // ── feuille (lame avec nervures) ───────────────────────────────────────────
  void _drawLeaf(
    Canvas canvas,
    _Leaf geom,
    double Function(double) widthFn,
    List<Color> fills,
    double rimAlpha,
  ) {
    const n = 44;
    final up = List.generate(
      n + 1,
      (i) => _cubic(geom.b, geom.c1, geom.c2, geom.tip, i / n),
    );
    Offset normal(int i) {
      final a = up[math.max(0, i - 1)], b = up[math.min(up.length - 1, i + 1)];
      var nx = -(b.y - a.y), ny = (b.x - a.x);
      final l = math.sqrt(nx * nx + ny * ny);
      if (l > 0) {
        nx /= l;
        ny /= l;
      }
      if (ny < 0) {
        nx = -nx;
        ny = -ny;
      }
      return Offset(nx, ny);
    }

    final path = Path();
    var p0 = _px(up[0]);
    path.moveTo(p0.dx, p0.dy);
    for (var i = 1; i <= n; i++) {
      final p = _px(up[i]);
      path.lineTo(p.dx, p.dy);
    }
    for (var i = n; i >= 0; i--) {
      final nrm = normal(i);
      final w = widthFn(i / n);
      final p = _px(_P(up[i].x + nrm.dx * w, up[i].y + nrm.dy * w));
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    // ombre douce
    canvas.drawPath(
      path.shift(Offset(0, S * 0.016)),
      Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, S * 0.012),
    );
    final b = _px(geom.b), t = _px(geom.tip);
    canvas.drawPath(
      path,
      Paint()..shader = ui.Gradient.linear(b, t, fills, const [0.0, 0.5, 1.0]),
    );
    if (rimAlpha > 0) {
      final rim = Path();
      var q = _px(up[0]);
      rim.moveTo(q.dx, q.dy);
      for (var i = 1; i <= n; i++) {
        q = _px(up[i]);
        rim.lineTo(q.dx, q.dy);
      }
      canvas.drawPath(
        rim,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = S * 0.005
          ..strokeCap = StrokeCap.round
          ..color = Color.fromRGBO(195, 238, 228, rimAlpha),
      );
    }
    // nervures
    final mid = Path();
    for (var i = 0; i <= n; i++) {
      final nrm = normal(i);
      final w = widthFn(i / n) * 0.5;
      final mp = _px(_P(up[i].x + nrm.dx * w, up[i].y + nrm.dy * w));
      i == 0 ? mid.moveTo(mp.dx, mp.dy) : mid.lineTo(mp.dx, mp.dy);
    }
    canvas.drawPath(
      mid,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = S * 0.004
        ..color = Color.fromRGBO(18, 52, 38, 0.6),
    );
    for (var k = 1; k <= 4; k++) {
      final s = k / 5;
      final i = (s * n).round();
      final nrm = normal(i);
      final w = widthFn(s);
      final a2 = _px(up[i]);
      final bv = _px(
        _P(up[i].x + nrm.dx * w * 0.92, up[i].y + nrm.dy * w * 0.92),
      );
      canvas.drawLine(
        a2,
        bv,
        Paint()
          ..strokeWidth = S * 0.0026
          ..color = Color.fromRGBO(18, 52, 38, 0.42),
      );
    }
  }

  // ── berge de mousse ────────────────────────────────────────────────────────
  void _mound(Canvas canvas) {
    final cx = 0.40 * W, base = _wl * H;
    const n = 40, halfW = 0.17, peak = 0.068;
    final pts = List.generate(n + 1, (i) {
      final t = i / n, x = (t * 2 - 1) * halfW;
      final env = math.pow(math.sin(math.pi * t), 0.6).toDouble();
      final bumps =
          (0.010 * math.sin(t * math.pi * 3.0) +
              0.006 * math.sin(t * math.pi * 6.3)) *
          env;
      return _P(x, -(peak * env + bumps));
    });
    // ombre sur l'eau
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, base + S * 0.012),
        width: S * 0.36,
        height: S * 0.048,
      ),
      Paint()..color = const Color(0x8C020C10),
    );
    // corps (volume par dégradé vertical)
    final body = Path();
    var p = Offset(cx + pts[0].x * S, base + pts[0].y * S);
    body.moveTo(p.dx, p.dy);
    for (var i = 1; i <= n; i++) {
      p = Offset(cx + pts[i].x * S, base + pts[i].y * S);
      body.lineTo(p.dx, p.dy);
    }
    body.lineTo(cx + halfW * S, base + S * 0.02);
    body.lineTo(cx - halfW * S, base + S * 0.02);
    body.close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, base - peak * S),
          Offset(0, base + S * 0.02),
          const [Color(0xFF5E9A52), Color(0xFF3C7846), Color(0xFF16331F)],
          const [0.0, 0.45, 1.0],
        ),
    );
    // occlusion ambiante en bas
    canvas.drawPath(
      body,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, base - S * 0.022),
          Offset(0, base + S * 0.02),
          const [Color(0x00081610), Color(0xB3081610)],
        ),
    );
    // duvet : brins dressés le long de la crête
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = S * 0.0026;
    for (final f in _moss) {
      final cpt = pts[(f.s * n).round()];
      final x = cx + cpt.x * S, y = base + cpt.y * S, len = f.len * S;
      final col = Color.fromRGBO(
        (40 + (140 - 40) * f.shade * 0.9).round(),
        (86 + (205 - 86) * f.shade * 0.9).round(),
        (50 + (120 - 50) * f.shade * 0.9).round(),
        0.55 + 0.4 * f.shade,
      );
      final fr = Path()
        ..moveTo(x, y)
        ..quadraticBezierTo(
          x + f.lean * len * 0.5,
          y - len * 0.55,
          x + f.lean * len,
          y - len,
        );
      canvas.drawPath(fr, stroke..color = col);
    }
    // liseré de lumière sur la crête
    final crest = Path();
    for (var i = 0; i <= n; i++) {
      final q = Offset(cx + pts[i].x * S, base + pts[i].y * S);
      i == 0 ? crest.moveTo(q.dx, q.dy) : crest.lineTo(q.dx, q.dy);
    }
    canvas.drawPath(
      crest,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = S * 0.0038
        ..color = const Color(0x33AAE196),
    );
  }

  // ── goutte ─────────────────────────────────────────────────────────────────
  void _drawDrop(Canvas canvas, _P pn, double r, double stretch, double glint) {
    final c = _px(pn);
    canvas.save();
    // halo
    canvas.drawCircle(
      c,
      r * 3.0,
      Paint()
        ..shader = ui.Gradient.radial(c, r * 3.0, const [
          Color(0x38BEEBF0),
          Color(0x00BEEBF0),
        ]),
    );
    canvas.translate(c.dx, c.dy);
    canvas.scale(1, stretch);
    final body = Path();
    if (stretch > 1.05) {
      body
        ..moveTo(0, -r * 1.5)
        ..cubicTo(r * 0.95, -r * 0.4, r, r * 0.7, 0, r)
        ..cubicTo(-r, r * 0.7, -r * 0.95, -r * 0.4, 0, -r * 1.5);
    } else {
      body.addOval(Rect.fromCircle(center: Offset.zero, radius: r));
    }
    body.close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(-r * 0.35, -r * 0.4),
          r * 1.2,
          const [Color(0xF2E1F8FA), Color(0xB396D2DC), Color(0x803C7887)],
          const [0.0, 0.45, 1.0],
        ),
    );
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.16
        ..color = const Color(0x80DCFAFF),
    );
    canvas.drawCircle(
      Offset(-r * 0.32, -r * 0.42),
      r * 0.26,
      Paint()..color = const Color(0xE6FFFFFF),
    );
    // reflet mobile
    final ga = glint * math.pi * 2;
    canvas.drawCircle(
      Offset(math.cos(ga) * r * 0.5, math.sin(ga) * r * 0.5 - r * 0.12),
      r * 0.12,
      Paint()..color = const Color(0xD9FFFFFF),
    );
    canvas.restore();
  }

  // ── impact dans l'eau ──────────────────────────────────────────────────────
  void _waterImpact(Canvas canvas, double cx, double cy, double et) {
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, _wl * H, W, H));
    final o = Offset(cx * W, cy * H);
    if (et < 0.22) {
      final s = et / 0.22;
      canvas.drawOval(
        Rect.fromCenter(
          center: o,
          width: S * 0.04 * (1 - s),
          height: S * 0.014 * (1 - s),
        ),
        Paint()..color = Color.fromRGBO(10, 30, 38, 0.5 * (1 - s)),
      );
      for (var i = 0; i < 6; i++) {
        final a = i / 6 * math.pi * 2, d = S * 0.04 * _easeOutQuad(s);
        final x = o.dx + math.cos(a) * d;
        final y = o.dy + math.sin(a) * d * 0.32 - S * 0.045 * s * (1 - s) * 3.5;
        canvas.drawCircle(
          Offset(x, y),
          S * 0.004 * (1 - s),
          Paint()..color = Color.fromRGBO(215, 246, 250, 0.75 * (1 - s)),
        );
      }
    }
    for (var k = 0; k < 4; k++) {
      final ph = et * 1.15 - k * 0.18;
      if (ph <= 0 || ph > 1) continue;
      final rad = S * (0.012 + _easeOutQuad(ph) * 0.22);
      canvas.drawOval(
        Rect.fromCenter(center: o, width: rad * 2, height: rad * 0.6),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = S * 0.0035 * (1 - ph * 0.6)
          ..color = Color.fromRGBO(180, 228, 236, 0.42 * (1 - ph)),
      );
    }
    canvas.restore();
  }

  // ── mot + éclat ────────────────────────────────────────────────────────────
  void _wordmark(Canvas canvas, double alpha) {
    if (alpha <= 0) return;
    final tp = TextPainter(
      text: TextSpan(
        text: 'DewDrop',
        style: TextStyle(
          color: Color.fromRGBO(220, 240, 244, 0.96 * alpha),
          fontSize: S * 0.072,
          fontWeight: FontWeight.w300,
          letterSpacing: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(W * 0.5 - tp.width / 2, H * 0.135 - tp.height));
  }

  void _wordSparkle(Canvas canvas, double t) {
    if (t < 0) return;
    final cx = W * 0.5, cy = H * 0.135 - S * 0.022;
    for (var i = 0; i < _spk.length; i++) {
      final pp = (t - i * 0.06) / 0.6;
      if (pp < 0 || pp > 1) continue;
      final k = math.sin(pp * math.pi);
      _spark(
        canvas,
        cx + _spk[i][0] * S,
        cy + _spk[i][1] * S,
        S * 0.026 * k,
        0.9 * k,
      );
    }
  }

  void _spark(Canvas canvas, double x, double y, double size, double alpha) {
    canvas.save();
    canvas.translate(x, y);
    final star = Path()
      ..moveTo(0, -size)
      ..lineTo(size * 0.22, -size * 0.22)
      ..lineTo(size, 0)
      ..lineTo(size * 0.22, size * 0.22)
      ..lineTo(0, size)
      ..lineTo(-size * 0.22, size * 0.22)
      ..lineTo(-size, 0)
      ..lineTo(-size * 0.22, -size * 0.22)
      ..close();
    canvas.drawPath(
      star,
      Paint()
        ..blendMode = BlendMode.plus
        ..color = Color.fromRGBO(220, 245, 255, alpha),
    );
    canvas.drawCircle(
      Offset.zero,
      size * 0.2,
      Paint()
        ..blendMode = BlendMode.plus
        ..color = Color.fromRGBO(255, 255, 255, alpha),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LoaderPainter old) => false;
}
