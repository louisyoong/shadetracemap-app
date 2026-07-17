import 'package:flutter/material.dart';

import 'root_shell.dart';

void main() {
  runApp(const ShadeTraceMapApp());
}

class ShadeTraceMapApp extends StatefulWidget {
  const ShadeTraceMapApp({super.key});

  @override
  State<ShadeTraceMapApp> createState() => _ShadeTraceMapAppState();
}

class _ShadeTraceMapAppState extends State<ShadeTraceMapApp> {
  ThemeMode _themeMode = ThemeMode.dark;

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
      home: RootShell(
        themeMode: _themeMode,
        onThemeModeChanged: (mode) => setState(() => _themeMode = mode),
      ),
    );
  }
}
