import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_widget_service.dart';
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

class _ShadeTraceMapAppState extends State<ShadeTraceMapApp>
    with WidgetsBindingObserver {
  ThemeMode _themeMode = ThemeMode.dark;
  late bool _onboardingComplete = widget.onboardingComplete;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Fire-and-forget: seeds the home-screen widget with today's sunset as
    // soon as the app has a location, without blocking first paint on it.
    HomeWidgetService.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Keeps the widget's sunset time fresh across day boundaries / location
    // changes without needing the user to open a specific tab for it.
    if (state == AppLifecycleState.resumed) {
      HomeWidgetService.sync();
    }
  }

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
