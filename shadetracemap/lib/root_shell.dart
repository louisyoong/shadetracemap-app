import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'settings_screen.dart';
import 'shade_map_screen.dart';
import 'sun_simulator_screen.dart';
import 'weather_screen.dart';

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
    final navTint = isDark ? const Color(0xFF15171C) : Colors.white;

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
          const WeatherScreen(),
          SettingsScreen(
            themeMode: widget.themeMode,
            onThemeModeChanged: widget.onThemeModeChanged,
          ),
        ],
      ),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
            ),
            child: NavigationBar(
              backgroundColor: navTint.withValues(alpha: 0.55),
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              selectedIndex: _tabIndex,
              onDestinationSelected: (i) => setState(() => _tabIndex = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.map_outlined),
                  selectedIcon: Icon(Icons.map),
                  label: 'ShadeMap',
                ),
                NavigationDestination(
                  icon: Icon(Icons.wb_sunny_outlined),
                  selectedIcon: Icon(Icons.wb_sunny),
                  label: 'Sun Simulator',
                ),
                NavigationDestination(
                  icon: Icon(Icons.cloud_outlined),
                  selectedIcon: Icon(Icons.cloud),
                  label: 'Weather',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
