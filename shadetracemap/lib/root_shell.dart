import 'package:flutter/material.dart';

import 'app_rating.dart';
import 'app_tab_bar.dart';
import 'compass_screen.dart';
import 'settings_screen.dart';
import 'shade_map_screen.dart';
import 'sun_simulator_screen.dart';
import 'weather_screen.dart';

const _tabAccent = Color(0xFFFFB300);

// Must match the "Settings" entry's position in _tabItems below.
const _settingsTabIndex = 4;

/// Light theme: a bright, near-white glass pill (close to the package's own
/// tuned default) - reads as a clean iOS-style frosted card against a light
/// background.
const _lightTabBarStyle = AppTabBarStyle(
  activeColor: _tabAccent,
  inactiveColor: Color(0xFF6B7078),
  indicatorGradientColors: [
    Color(0x2EFFB300), // _tabAccent @ 18%
    Color(0x8CFFFFFF), // white @ 55%
    Color(0x40FFFFFF), // white @ 25%
  ],
  indicatorBorderColor: Color(0xB3FFFFFF), // white @ 70%
  indicatorGlowColor: Color(0xCCFFFFFF), // white @ 80%
  outerBorderColor: Color(0xD9FFFFFF), // white @ 85%
  // Plain frosted glass (the same BackdropFilter blur GlassPanel uses
  // everywhere else) rather than the liquid_glass_renderer package's custom
  // shader this used to use - that shader can't correctly render over a
  // native platform view (e.g. the Shade Map's map) sitting behind it, and
  // its lensing/glow settings pushed past the package's own defaults made
  // that worse. A plain blur+tint is reliable everywhere the bar floats.
  glassTint: Colors.white,
  glassTintOpacity: 0.7,
  blurSigma: 18,
  padding: EdgeInsets.zero,
);

/// Dark theme: a navy-tinted, more see-through glass (matching sun_math's
/// own "night sky" gradient colour elsewhere in the app) with an
/// amber-tinted indicator instead of the package default's bright white
/// blob/outline, which read as mismatched floating over dark content.
const _darkTabBarStyle = AppTabBarStyle(
  activeColor: _tabAccent,
  inactiveColor: Color(0xFF9AA0A8),
  indicatorGradientColors: [
    Color(0x59FFB300), // _tabAccent @ 35%
    Color(0x2EFFB300), // _tabAccent @ 18%
    Color(0x0FFFFFFF), // white @ 6%
  ],
  indicatorBorderColor: Color(0x73FFB300), // _tabAccent @ 45%
  indicatorGlowColor: Color(0x24FFFFFF), // white @ 14%
  outerBorderColor: Color(0x1AFFFFFF), // white @ 10%
  outerBorderWidth: 1.2,
  // See the light style's glassTint comment above.
  glassTint: Color(0xFF171F38),
  glassTintOpacity: 0.55,
  blurSigma: 20,
  padding: EdgeInsets.zero,
);

const _tabItems = [
  LiquidGlassBarItem(iconData: Icons.map_outlined, label: 'ShadeMap'),
  LiquidGlassBarItem(iconData: Icons.wb_sunny_outlined, label: 'Sun Path'),
  LiquidGlassBarItem(iconData: Icons.explore_outlined, label: 'Compass'),
  LiquidGlassBarItem(iconData: Icons.cloud_outlined, label: 'Weather'),
  LiquidGlassBarItem(iconData: Icons.settings_outlined, label: 'Settings'),
];

class RootShell extends StatefulWidget {
  const RootShell({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      // Lets each tab's body draw full-bleed behind the nav bar instead of
      // stopping above it - required for the bar to read as glass floating
      // over content rather than an opaque strip beneath it. Flutter widens
      // MediaQuery.padding.bottom for the body accordingly, so each tab's
      // existing bottom-inset handling keeps working unchanged.
      extendBody: true,
      // IndexedStack keeps every tab's widget tree (and state) alive across
      // switches instead of tearing it down - important here since the
      // ShadeMap tab holds an expensive native map view and in-flight
      // shadow computations that shouldn't reset every time you tap away.
      body: IndexedStack(
        index: _tabIndex,
        children: [
          const ShadeMapScreen(),
          const SunSimulatorScreen(),
          const CompassScreen(),
          const WeatherScreen(),
          SettingsScreen(
            themeMode: widget.themeMode,
            onThemeModeChanged: widget.onThemeModeChanged,
          ),
        ],
      ),
      bottomNavigationBar: AppTabBar(
        currentIndex: _tabIndex,
        onTap: (i) {
          setState(() => _tabIndex = i);
          if (i == _settingsTabIndex) {
            maybeShowRatingDialog(context);
          }
        },
        style: (isDark ? _darkTabBarStyle : _lightTabBarStyle).copyWith(
          // Matches the bottom-bar spacing every other screen in the app
          // already uses (10 + the device's own safe-area inset) instead
          // of a fixed guess that over/under-shoots depending on device.
          padding: EdgeInsets.fromLTRB(
            16,
            10,
            16,
            10 + MediaQuery.of(context).padding.bottom,
          ),
        ),
        items: _tabItems,
      ),
    );
  }
}
