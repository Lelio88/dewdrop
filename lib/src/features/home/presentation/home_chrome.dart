import 'dart:ui';

import 'package:dewdrop/src/common/seasonal.dart';
import 'package:flutter/material.dart';

/// The small floating pieces laid over the live decor: the ☰ button, the two
/// pull handles, and the marronnier badge. Kept together because they share one
/// job — sitting on top of a decor that can be any colour, and staying legible
/// there without hiding it.
class GlassCircleButton extends StatelessWidget {
  const GlassCircleButton({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final white = Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: white.withValues(alpha: 0.14),
              border: Border.all(color: white.withValues(alpha: 0.28)),
            ),
            child: Icon(icon, color: white.withValues(alpha: 0.9), size: 24),
          ),
        ),
      ),
    );
  }
}

/// A very discreet pull handle (a thin, faint bar) hinting the swipe gestures.
/// The 12 px padding gives a comfortable tap target without making it look big.
class HomeHandle extends StatelessWidget {
  const HomeHandle({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          width: 34,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// A small glass pill shown on the home while a marronnier locks the world,
/// e.g. "🎃 Halloween". Explains why the universe can't be changed today.
class SeasonalBadge extends StatelessWidget {
  const SeasonalBadge({super.key, required this.event});

  final SeasonalEvent event;

  @override
  Widget build(BuildContext context) {
    final w = Colors.white;
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            color: Colors.black.withValues(alpha: 0.28),
            border: Border.all(color: w.withValues(alpha: 0.22)),
          ),
          child: Text(
            '${event.emoji}  ${event.label}',
            style: TextStyle(
              color: w.withValues(alpha: 0.92),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}
