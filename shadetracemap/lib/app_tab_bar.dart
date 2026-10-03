import 'package:flutter/material.dart';
import 'package:liquid_glass_bar/liquid_glass_bar.dart' show LiquidGlassBarItem;

import 'glass_panel.dart';

export 'package:liquid_glass_bar/liquid_glass_bar.dart' show LiquidGlassBarItem;

/// Theme-aware styling for [AppTabBar].
///
/// Forked from the `liquid_glass_bar` pub package (MIT-licensed) rather than
/// just wrapping it, because that package hardcodes the selection
/// indicator's fill/border/glow - and the bar's own rim border - to a fixed
/// white regardless of `activeColor` or the app's theme. That reads fine
/// floating over a light background, but shows up as a mismatched bright
/// blob/outline over a dark one. Forking exposes those colors so each theme
/// gets a palette actually designed for it instead of one look bent to fit
/// both.
class AppTabBarStyle {
  final Color activeColor;
  final Color inactiveColor;
  final List<Color> indicatorGradientColors;
  final Color indicatorBorderColor;
  final Color indicatorGlowColor;
  final Color outerBorderColor;
  final double outerBorderWidth;
  final Color glassTint;
  final double glassTintOpacity;
  final double blurSigma;
  final double borderRadius;
  final double height;
  final EdgeInsets padding;
  final Duration animationDuration;
  final Curve animationCurve;
  final double iconSize;
  final double selectedIconScale;

  const AppTabBarStyle({
    required this.activeColor,
    required this.inactiveColor,
    required this.indicatorGradientColors,
    required this.indicatorBorderColor,
    required this.indicatorGlowColor,
    required this.outerBorderColor,
    required this.glassTint,
    this.glassTintOpacity = 0.55,
    this.blurSigma = 18,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 10),
    this.outerBorderWidth = 1.5,
    this.borderRadius = 28,
    this.height = 54,
    this.animationDuration = const Duration(milliseconds: 250),
    this.animationCurve = Curves.easeOutQuad,
    this.iconSize = 24,
    this.selectedIconScale = 1.15,
  });

  /// Used to apply the device's actual safe-area inset to [padding] at
  /// build time, since that value isn't known when the base light/dark
  /// style constants are declared.
  AppTabBarStyle copyWith({EdgeInsets? padding}) => AppTabBarStyle(
    activeColor: activeColor,
    inactiveColor: inactiveColor,
    indicatorGradientColors: indicatorGradientColors,
    indicatorBorderColor: indicatorBorderColor,
    indicatorGlowColor: indicatorGlowColor,
    outerBorderColor: outerBorderColor,
    outerBorderWidth: outerBorderWidth,
    glassTint: glassTint,
    glassTintOpacity: glassTintOpacity,
    blurSigma: blurSigma,
    borderRadius: borderRadius,
    height: height,
    padding: padding ?? this.padding,
    animationDuration: animationDuration,
    animationCurve: animationCurve,
    iconSize: iconSize,
    selectedIconScale: selectedIconScale,
  );
}

/// A liquid-glass bottom tab bar with a sliding selection indicator and
/// drag-to-switch gesture, styled per [style] rather than a fixed palette.
class AppTabBar extends StatefulWidget {
  const AppTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    required this.style,
  }) : assert(items.length >= 2, 'At least 2 items are required.');

  final List<LiquidGlassBarItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final AppTabBarStyle style;

  @override
  State<AppTabBar> createState() => _AppTabBarState();
}

class _AppTabBarState extends State<AppTabBar> {
  double? _dragAlignment;
  bool _isDragging = false;
  int? _highlightedIndex;

  int get _lastIndex => widget.items.length - 1;

  double _getAlignment(int index) {
    if (_lastIndex == 0) return 0.0;
    return -1.0 + (index * 2 / _lastIndex);
  }

  void _updateHighlightedIndex() {
    if (!_isDragging || _dragAlignment == null) {
      _highlightedIndex = null;
      return;
    }
    final normalized = (_dragAlignment! + 1) / 2;
    _highlightedIndex = (normalized * _lastIndex).round().clamp(0, _lastIndex);
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final itemCount = widget.items.length;

    return Container(
      padding: style.padding,
      child: Stack(
        children: [
          // Plain BackdropFilter-based glass (the same technique GlassPanel
          // uses for every other floating panel in the app) rather than the
          // liquid_glass_renderer package's custom shader this used to use.
          // That shader renders itself into its own compositing layer,
          // which can't correctly capture a native platform view (e.g. the
          // Shade Map's map) sitting directly behind it - it showed up as a
          // flat grey box there instead of glass. Plain BackdropFilter blur
          // doesn't have that limitation (GlassPanel's own search bar/
          // legend/bottom bar already render fine over the live map), so
          // this trades the shader's lensing/refraction bend for reliability
          // everywhere the bar might float.
          GlassPanel(
            borderRadius: style.borderRadius,
            tint: style.glassTint,
            tintOpacity: style.glassTintOpacity,
            blurSigma: style.blurSigma,
            padding: EdgeInsets.zero,
            child: Container(
              padding: const EdgeInsets.all(6),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final itemWidth = constraints.maxWidth / itemCount;
                  final totalDragWidth = constraints.maxWidth - itemWidth;

                  return GestureDetector(
                    onHorizontalDragStart: (details) {
                      setState(() {
                        _isDragging = true;
                        _dragAlignment = _getAlignment(widget.currentIndex);
                        _updateHighlightedIndex();
                      });
                    },
                    onHorizontalDragUpdate: (details) {
                      if (!_isDragging) return;
                      setState(() {
                        final deltaAlignment =
                            (details.primaryDelta! / totalDragWidth) * 2.0;
                        _dragAlignment = (_dragAlignment! + deltaAlignment)
                            .clamp(-1.0, 1.0);
                        _updateHighlightedIndex();
                      });
                    },
                    onHorizontalDragEnd: (details) {
                      setState(() {
                        _isDragging = false;
                        _highlightedIndex = null;
                        final normalized = (_dragAlignment! + 1) / 2;
                        widget.onTap(
                          (normalized * _lastIndex).round().clamp(
                            0,
                            _lastIndex,
                          ),
                        );
                      });
                    },
                    onHorizontalDragCancel: () {
                      setState(() {
                        _isDragging = false;
                        _highlightedIndex = null;
                      });
                    },
                    child: SizedBox(
                      height: style.height,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedAlign(
                            duration: _isDragging
                                ? Duration.zero
                                : style.animationDuration,
                            curve: style.animationCurve,
                            alignment: Alignment(
                              _isDragging
                                  ? _dragAlignment!
                                  : _getAlignment(widget.currentIndex),
                              0,
                            ),
                            child: Container(
                              width: itemWidth,
                              height: 50,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: style.indicatorGradientColors,
                                  stops: const [0.0, 0.4, 1.0],
                                ),
                                border: Border.all(
                                  color: style.indicatorBorderColor,
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: style.activeColor.withValues(
                                      alpha: 0.25,
                                    ),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                  BoxShadow(
                                    color: style.indicatorGlowColor,
                                    blurRadius: 8,
                                    offset: const Offset(-2, -2),
                                  ),
                                ],
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              for (var i = 0; i < itemCount; i++)
                                _TabItem(
                                  item: widget.items[i],
                                  isSelected: widget.currentIndex == i,
                                  isHighlighted: _highlightedIndex == i,
                                  onTap: () => widget.onTap(i),
                                  style: style,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(style.borderRadius),
                  border: Border.all(
                    color: style.outerBorderColor,
                    width: style.outerBorderWidth,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.item,
    required this.isSelected,
    required this.isHighlighted,
    required this.onTap,
    required this.style,
  });

  final LiquidGlassBarItem item;
  final bool isSelected;
  final bool isHighlighted;
  final VoidCallback onTap;
  final AppTabBarStyle style;

  @override
  Widget build(BuildContext context) {
    final isActive = isSelected || isHighlighted;
    final color = isActive ? style.activeColor : style.inactiveColor;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: isSelected ? style.selectedIconScale : 1.0,
                duration: const Duration(milliseconds: 500),
                curve: Curves.elasticOut,
                child: TweenAnimationBuilder<Color?>(
                  duration: style.animationDuration,
                  curve: style.animationCurve,
                  tween: ColorTween(begin: style.inactiveColor, end: color),
                  builder: (context, animatedColor, _) => Icon(
                    item.iconData,
                    size: style.iconSize,
                    color: animatedColor,
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: SizedBox(
                  height: isSelected ? 0 : null,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: isSelected ? 0.0 : 1.0,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        item.label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w400,
                          height: 16 / 10,
                          color: color,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
