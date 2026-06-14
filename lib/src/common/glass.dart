import 'dart:ui';

import 'package:flutter/material.dart';

/// Frosted-glass surface (glassmorphism) — the app's signature UI material.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.radius = 26,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final w = Colors.white;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [w.withValues(alpha: 0.16), w.withValues(alpha: 0.06)],
            ),
            border: Border.all(color: w.withValues(alpha: 0.24), width: 1.2),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Glass-styled text field.
class GlassTextField extends StatelessWidget {
  const GlassTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
    this.icon,
    this.autofillHints,
    this.focusNode,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final IconData? icon;
  final List<String>? autofillHints;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final w = Colors.white;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      obscureText: obscure,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      style: TextStyle(color: w),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: w.withValues(alpha: 0.5)),
        prefixIcon:
            icon == null ? null : Icon(icon, color: w.withValues(alpha: 0.6), size: 20),
        filled: true,
        fillColor: w.withValues(alpha: 0.08),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: w.withValues(alpha: 0.18)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: w.withValues(alpha: 0.45)),
        ),
      ),
    );
  }
}

/// Glass primary button with a loading state.
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final w = Colors.white;
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: w.withValues(alpha: 0.22),
          border: Border.all(color: w.withValues(alpha: 0.35)),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(
                label,
                style: TextStyle(
                  color: w,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
      ),
    );
  }
}
