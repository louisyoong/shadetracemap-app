import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_screen.dart';
import 'root_shell.dart';

const _onboardingCompleteKey = 'has_completed_onboarding';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final onboardingComplete = prefs.getBool(_onboardingCompleteKey) ?? false;
  runApp(ShadeTraceMapApp(onboardingComplete: onboardingComplete));
}

class ShadeTraceMapApp extends StatefulWidget {
  const ShadeTraceMapApp({super.key, required this.onboardingComplete});

  final bool onboardingComplete;

  @override
  State<ShadeTraceMapApp> createState() => _ShadeTraceMapAppState();
}

class _ShadeTraceMapAppState extends State<ShadeTraceMapApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  late bool _onboardingComplete = widget.onboardingComplete;

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingCompleteKey, true);
    setState(() => _onboardingComplete = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shade Map Demo',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: const Color(0xFF3B7CFF),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF3B7CFF),
      ),
      home: _onboardingComplete
          ? RootShell(
              themeMode: _themeMode,
              onThemeModeChanged: (mode) => setState(() => _themeMode = mode),
            )
          : OnboardingScreen(onGetStarted: _completeOnboarding),
    );
  }
}
