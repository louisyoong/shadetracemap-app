import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A translucent "frosted glass" panel: blurs whatever is behind it before
/// applying a tinted, semi-transparent fill. Shared by every floating piece
/// of chrome across the app so the blur/tint/border/shadow treatment stays
/// consistent.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = 14,
    this.shape = BoxShape.rectangle,
    this.tintOpacity = 0.55,
    this.blurSigma = 18,
    this.padding,
    this.tint,
  });

  final Widget child;
  final double borderRadius;
  final BoxShape shape;
  final double tintOpacity;
  final double blurSigma;
  final EdgeInsetsGeometry? padding;

  /// Overrides the default tint color. Defaults to a dark tint regardless
  /// of theme brightness - the map screen's chrome is intentionally
  /// dark-styled per the app's original "dark UI, map-first" design, same
  /// as most map apps keep map chrome dark even in system light mode.
  final Color? tint;

  static const _defaultTint = Color(0xFF15171C);

  @override
  Widget build(BuildContext context) {
    final tintColor = tint ?? _defaultTint;
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tintColor.withValues(alpha: tintOpacity),
        shape: shape,
        borderRadius: shape == BoxShape.circle
            ? null
            : BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D000000),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
    final blurred = BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
      child: content,
    );
    return shape == BoxShape.circle
        ? ClipOval(child: blurred)
        : ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: blurred,
          );
  }
}
