import 'package:flutter/material.dart';

/// Shared design tokens and small building blocks used across every screen,
/// so recurring pieces - muted/primary text colors per theme, uppercase
/// section labels, stat readouts with an icon badge, a location chip - stay
/// visually identical everywhere instead of drifting screen to screen as
/// each one hand-rolled its own copy.

// Text colors paired per theme brightness. Shared by every screen that
// tints its own background live (weather/compass/sun path/shade map)
// instead of relying on default Material on-surface colors, which don't
// track a custom gradient backdrop's contrast the same way.
const kLightText = Color(0xFF2A2620);
const kLightTextMuted = Color(0x992A2620);
const kDarkText = Color(0xFFF3F1EC);
const kDarkTextMuted = Color(0x99F3F1EC);

Color textColorFor(bool isDark) => isDark ? kDarkText : kLightText;
Color textMutedFor(bool isDark) => isDark ? kDarkTextMuted : kLightTextMuted;

// Corner radius for the app's major floating glass panels/hero cards - a
// touch softer/rounder than the original 14-18px so cards read closer to
// the pillowy, generous rounding style apps like Lumy use.
const kCardRadius = 22.0;
const kChipRadius = 999.0;

/// A small uppercase, letter-spaced label used to head off a grouped
/// section (e.g. "APPEARANCE", "ABOUT") - one definition instead of each
/// screen hand-rolling its own matching TextStyle.
class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    super.key,
    required this.color,
    this.fontSize = 11,
  });

  final String text;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}

/// A single stat readout - an icon in a soft tinted circular badge, a bold
/// value, and an uppercase label underneath - shared by every screen that
/// shows a row of small stats (sunrise/sunset/UV, altitude/azimuth/heading,
/// etc.) so they all read as the same family of component instead of each
/// screen's own bespoke icon-value-label column.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.textColor,
    required this.textMuted,
    this.accent,
    this.valueColor,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color textColor;
  final Color textMuted;
  final Color? accent;
  final Color? valueColor;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final badgeColor = accent ?? textColor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 14, color: badgeColor),
        ),
        const SizedBox(height: 7),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? textColor,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

/// A rounded "chip" showing the current location with a pin icon, used in
/// place of a plain centered text caption on the tabs that follow a live
/// location (Weather, Compass, Sun Path) - reads as a considered piece of
/// chrome rather than a stray label floating over the gradient.
class LocationChip extends StatelessWidget {
  const LocationChip({
    super.key,
    required this.label,
    required this.textColor,
    required this.isDark,
  });

  final String label;
  final Color textColor;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(kChipRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.location_on_rounded,
            size: 13,
            color: textColor.withValues(alpha: 0.75),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
