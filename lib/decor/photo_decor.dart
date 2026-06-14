import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:dewdrop/decor/environment.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Photo scenes live under `assets/photo/{env}/{variant}/`, files named
/// `0.png` (farthest background) … `N.png` (closest foreground). Layers are
/// auto-discovered from the bundled asset manifest at runtime — just drop the
/// files in and relaunch; no code change needed.
///
/// Photo (parallax) renderer: layered images per scene shifted by
/// pointer/gyroscope to create 2.5-D depth, with an environment-appropriate
/// animated overlay (falling leaves / petals / spores / bubbles / stars) on
/// top so the photo breathes. A "pensée" (tap) sends a burst. Falls back to a
/// labelled placeholder until assets are added.
class PhotoDecor extends StatefulWidget {
  const PhotoDecor({
    super.key,
    required this.environment,
    this.variant = 0,
    this.child,
  });

  final Environment environment;
  final int variant;
  final Widget? child;

  @override
  State<PhotoDecor> createState() => _PhotoDecorState();
}

class _PhotoDecorState extends State<PhotoDecor>
    with SingleTickerProviderStateMixin {
  final _model = _PhotoModel();
  final math.Random _rng = math.Random(42);

  late final Ticker _ticker;
  late _Overlay _overlay;
  late List<_Particle> _particles;

  List<String> _layers = const [];
  double _lastTick = 0;
  Size _size = Size.zero;
  Offset _pointerLook = Offset.zero;

  @override
  void initState() {
    super.initState();
    _overlay = _overlayFor(widget.environment, widget.variant);
    _particles = _genParticles();
    _ticker = createTicker(_onTick)..start();
    _loadLayers();
  }

  @override
  void didUpdateWidget(PhotoDecor old) {
    super.didUpdateWidget(old);
    if (old.environment != widget.environment || old.variant != widget.variant) {
      _overlay = _overlayFor(widget.environment, widget.variant);
      _particles = _genParticles();
      _layers = const [];
      _loadLayers();
    }
  }

  Future<void> _loadLayers() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final prefix = 'assets/photo/${widget.environment.name}/${widget.variant}/';
    final layers = manifest
        .listAssets()
        .where((a) => a.startsWith(prefix) && _isLayer(a))
        .toList()
      ..sort();
    if (!mounted) return;
    setState(() => _layers = layers);
  }

  // Only numerically-named files are layers (0.png, 1.png, …). Source images
  // like `base.png` and `.gitkeep` are ignored.
  static final _layerRe = RegExp(r'^\d+\.(png|jpe?g|webp)$');
  bool _isLayer(String path) =>
      _layerRe.hasMatch(path.split('/').last.toLowerCase());

  void _onTick(Duration elapsed) {
    final now = elapsed.inMicroseconds / 1e6;
    final dt = (now - _lastTick).clamp(0.0, 0.05);
    _lastTick = now;
    _model.time = now;

    final auto = Offset(math.sin(now * 0.06) * 0.05, math.cos(now * 0.05) * 0.03);
    final target = auto + _pointerLook;
    final k = 1 - math.exp(-dt * 3);
    _model.look = Offset.lerp(_model.look, target, k)!;

    final rise = _overlay.kind == _PKind.bubble;
    final remove = <_Particle>[];
    for (final p in _particles) {
      if (!p.fixed) p.y += (rise ? -1 : 1) * p.speed * dt;
      p.rot += p.rotSpeed * dt;
      final out = rise ? p.y < -0.06 : p.y > 1.06;
      if (out) {
        if (p.ephemeral) {
          remove.add(p);
        } else {
          p.y = rise ? 1.06 : -0.06;
          p.x = _rng.nextDouble();
        }
      }
    }
    if (remove.isNotEmpty) _particles.removeWhere(remove.contains);
    _model.notify();
  }

  void _updatePointer(PointerEvent event) {
    if (_size == Size.zero) return;
    final nx = (event.localPosition.dx / _size.width) * 2 - 1;
    final ny = (event.localPosition.dy / _size.height) * 2 - 1;
    _pointerLook = Offset(-nx, -ny);
  }

  void _onTap() {
    _model.flashStart = _model.time;
    final rise = _overlay.kind == _PKind.bubble;
    for (var i = 0; i < 16; i++) {
      _particles.add(
        _Particle(
          x: _rng.nextDouble(),
          y: rise ? 1.05 + _rng.nextDouble() * 0.1 : -0.05 - _rng.nextDouble() * 0.18,
          size: _pSize(_overlay.kind) * 1.1,
          speed: _pSpeed(_overlay.kind) * 1.8 + 0.05,
          phase: _rng.nextDouble() * math.pi * 2,
          rot: _rng.nextDouble() * math.pi * 2,
          rotSpeed: (_rng.nextDouble() - 0.5) * 3,
          swayAmp: 0.02 + _rng.nextDouble() * 0.03,
          twinkleSpeed: 0.5 + _rng.nextDouble() * 1.5,
          fixed: false,
          ephemeral: true,
        ),
      );
    }
    HapticFeedback.lightImpact();
  }

  List<_Particle> _genParticles() => List.generate(_overlay.count, (_) {
        return _Particle(
          x: _rng.nextDouble(),
          y: _rng.nextDouble(),
          size: _pSize(_overlay.kind),
          speed: _pSpeed(_overlay.kind),
          phase: _rng.nextDouble() * math.pi * 2,
          rot: _rng.nextDouble() * math.pi * 2,
          rotSpeed: (_rng.nextDouble() - 0.5) * 1.6,
          swayAmp: 0.005 + _rng.nextDouble() * 0.02,
          twinkleSpeed: 0.5 + _rng.nextDouble() * 1.5,
          fixed: _overlay.kind == _PKind.star,
          ephemeral: false,
        );
      });

  double _pSize(_PKind kind) => switch (kind) {
        _PKind.bubble => 1.5 + _rng.nextDouble() * 4,
        _PKind.leaf || _PKind.petal => 3 + _rng.nextDouble() * 5,
        _PKind.star || _PKind.dust || _PKind.spore => 0.8 + _rng.nextDouble() * 1.8,
      };

  double _pSpeed(_PKind kind) => switch (kind) {
        _PKind.bubble => 0.04 + _rng.nextDouble() * 0.06,
        _PKind.leaf || _PKind.petal => 0.03 + _rng.nextDouble() * 0.05,
        _PKind.spore || _PKind.dust => 0.01 + _rng.nextDouble() * 0.03,
        _PKind.star => 0,
      };

  @override
  void dispose() {
    _ticker.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerHover: _updatePointer,
      onPointerMove: _updatePointer,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _size = constraints.biggest;
          return Stack(
            children: [
              Positioned.fill(
                child: _layers.isEmpty
                    ? _PlaceholderScene(
                        model: _model,
                        environment: widget.environment,
                        variant: widget.variant,
                      )
                    : _ImageParallax(layers: _layers, model: _model),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _OverlayPainter(_model, _particles, _overlay),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _onTap,
                ),
              ),
              if (widget.child != null) Positioned.fill(child: widget.child!),
            ],
          );
        },
      ),
    );
  }
}

class _PhotoModel extends ChangeNotifier {
  double time = 0;
  Offset look = Offset.zero;
  double flashStart = -10;
  void notify() => notifyListeners();
}

// ── Overlay (animated particles over the photo) ──────────────────────────────

enum _PKind { leaf, petal, spore, bubble, star, dust }

class _Overlay {
  const _Overlay(this.kind, this.color, this.count);
  final _PKind kind;
  final Color color;
  final int count;
}

_Overlay _overlayFor(Environment env, int variant) => switch (env) {
      Environment.space => const _Overlay(_PKind.star, Color(0xFFFFFFFF), 70),
      Environment.underwater =>
        const _Overlay(_PKind.bubble, Color(0xFFCFEFFF), 16),
      Environment.forest => switch (variant) {
          0 => const _Overlay(_PKind.leaf, Color(0xFFB8A24E), 24),
          1 => const _Overlay(_PKind.petal, Color(0xFFFFC2DC), 28),
          _ => const _Overlay(_PKind.spore, Color(0xFFE8F0C0), 22),
        },
      Environment.beach => const _Overlay(_PKind.dust, Color(0xFFFFF2D8), 18),
      Environment.library => const _Overlay(_PKind.dust, Color(0xFFFFE0A8), 30),
      Environment.mountain => const _Overlay(_PKind.dust, Color(0xFFFFFFFF), 20),
      Environment.desert => const _Overlay(_PKind.star, Color(0xFFEAF2FF), 40),
    };

class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.phase,
    required this.rot,
    required this.rotSpeed,
    required this.swayAmp,
    required this.twinkleSpeed,
    required this.fixed,
    required this.ephemeral,
  });
  double x;
  double y;
  double rot;
  final double size;
  final double speed;
  final double phase;
  final double rotSpeed;
  final double swayAmp;
  final double twinkleSpeed;
  final bool fixed; // static (twinkles in place)
  final bool ephemeral;
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.model, this.particles, this.overlay)
      : super(repaint: model);

  final _PhotoModel model;
  final List<_Particle> particles;
  final _Overlay overlay;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final time = model.time;
    final kind = overlay.kind;
    final color = overlay.color;

    for (final p in particles) {
      final px = (p.x + math.sin(time * 0.7 + p.phase) * p.swayAmp) * w;
      final py = p.y * h;
      switch (kind) {
        case _PKind.star:
        case _PKind.dust:
        case _PKind.spore:
          final tw = 0.5 + 0.5 * math.sin(time * p.twinkleSpeed + p.phase);
          final a = (0.7 * tw).clamp(0.0, 1.0);
          canvas.drawCircle(Offset(px, py), p.size * 2.4,
              Paint()..color = color.withValues(alpha: a * 0.18));
          canvas.drawCircle(Offset(px, py), p.size,
              Paint()..color = color.withValues(alpha: a));
        case _PKind.bubble:
          canvas.drawCircle(
            Offset(px, py),
            p.size,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = color.withValues(alpha: 0.55),
          );
          canvas.drawCircle(Offset(px - p.size * 0.3, py - p.size * 0.3),
              p.size * 0.28, Paint()..color = Colors.white.withValues(alpha: 0.6));
        case _PKind.leaf:
        case _PKind.petal:
          canvas.save();
          canvas.translate(px, py);
          canvas.rotate(p.rot);
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size * 1.7,
              height: p.size * (kind == _PKind.petal ? 0.7 : 0.9),
            ),
            Paint()..color = color.withValues(alpha: 0.9),
          );
          canvas.restore();
      }
    }

    // Soft flash when a "pensée" arrives.
    final ft = (time - model.flashStart) / 0.7;
    if (ft >= 0 && ft < 1) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..blendMode = BlendMode.plus
          ..color = color.withValues(alpha: (1 - ft) * 0.12),
      );
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => old.overlay.kind != overlay.kind;
}

// ── Real parallax (when assets exist) ────────────────────────────────────────

/// Each image layer shifts by an amount proportional to its depth (front
/// layers move most). Layers are slightly over-scaled so edges never show.
class _ImageParallax extends StatelessWidget {
  const _ImageParallax({required this.layers, required this.model});

  final List<String> layers;
  final _PhotoModel model;

  static const double _maxShift = 34;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: model,
      builder: (context, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < layers.length; i++)
              Transform.translate(
                // Back layer (0) stays anchored; front layers move the most.
                offset: model.look *
                    (layers.length == 1 ? 0.4 : i / (layers.length - 1)) *
                    _maxShift,
                child: Transform.scale(
                  scale: 1.12,
                  child: Image.asset(layers[i], fit: BoxFit.cover),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Placeholder (until assets exist) ─────────────────────────────────────────

class _PlaceholderScene extends StatelessWidget {
  const _PlaceholderScene({
    required this.model,
    required this.environment,
    required this.variant,
  });

  final _PhotoModel model;
  final Environment environment;
  final int variant;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _PlaceholderPainter(model, _paletteFor(environment))),
        Center(child: _InfoCard(environment: environment, variant: variant)),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.environment, required this.variant});

  final Environment environment;
  final int variant;

  @override
  Widget build(BuildContext context) {
    final white = Colors.white;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: white.withValues(alpha: 0.12),
            border: Border.all(color: white.withValues(alpha: 0.25), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_library_outlined,
                  color: white.withValues(alpha: 0.85), size: 26),
              const SizedBox(height: 12),
              Text('Mode Photo',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600, color: white)),
              const SizedBox(height: 4),
              Text('${environment.label} · Var ${variant + 1}',
                  style:
                      TextStyle(fontSize: 13, color: white.withValues(alpha: 0.7))),
              const SizedBox(height: 14),
              Text('Dépose 3–5 images (PNG, fond → avant) :',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12.5, color: white.withValues(alpha: 0.8))),
              const SizedBox(height: 6),
              Text(
                'assets/photo/${environment.name}/$variant/',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceholderPainter extends CustomPainter {
  _PlaceholderPainter(this.model, this.palette) : super(repaint: model);

  final _PhotoModel model;
  final _Palette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final lx = model.look.dx;
    final ly = model.look.dy;

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.top, palette.bottom],
        ).createShader(Offset.zero & size),
    );

    final mid = Offset(lx * 16, ly * 10);
    for (var i = 0; i < 5; i++) {
      final cx = (i + 0.5) / 5 * w + mid.dx;
      canvas.drawCircle(Offset(cx, h * 0.45 + mid.dy), h * 0.18,
          Paint()..color = palette.mid.withValues(alpha: 0.5));
    }

    final fg = Offset(lx * 30, ly * 18);
    final path = Path()
      ..moveTo(0, h)
      ..lineTo(0, h * 0.78 + fg.dy)
      ..quadraticBezierTo(w * 0.5 + fg.dx, h * 0.7 + fg.dy, w, h * 0.8 + fg.dy)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(path, Paint()..color = palette.front);
  }

  @override
  bool shouldRepaint(_PlaceholderPainter old) => old.palette != palette;
}

class _Palette {
  const _Palette(this.top, this.bottom, this.mid, this.front);
  final Color top;
  final Color bottom;
  final Color mid;
  final Color front;
}

_Palette _paletteFor(Environment env) => switch (env) {
      Environment.space => const _Palette(
          Color(0xFF101830), Color(0xFF05050C), Color(0xFF3A3A6A), Color(0xFF02030A)),
      Environment.underwater => const _Palette(
          Color(0xFF1C7FA0), Color(0xFF02101A), Color(0xFF2E6E82), Color(0xFF021018)),
      Environment.forest => const _Palette(
          Color(0xFF6E8E4E), Color(0xFF16200E), Color(0xFF3C5A2A), Color(0xFF0C140A)),
      Environment.beach => const _Palette(
          Color(0xFF7EC8E3), Color(0xFFE3C48E), Color(0xFFBFA878), Color(0xFF8A6A44)),
      Environment.library => const _Palette(
          Color(0xFF3A2A1E), Color(0xFF140D08), Color(0xFF6A4A2A), Color(0xFF0A0604)),
      Environment.mountain => const _Palette(
          Color(0xFFE5A6A0), Color(0xFF243A52), Color(0xFF5A7088), Color(0xFF0E1622)),
      Environment.desert => const _Palette(
          Color(0xFF2A2440), Color(0xFF1A1208), Color(0xFF5A4A2A), Color(0xFF12100A)),
    };
