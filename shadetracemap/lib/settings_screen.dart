import 'package:flutter/material.dart';

import 'glass_panel.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final panelTint = isDark ? const Color(0xFF15171C) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF171922), const Color(0xFF0A0B0E)]
              : [const Color(0xFFEAF2FF), const Color(0xFFF7F8FA)],
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          children: [
            Text(
              'Settings',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'APPEARANCE',
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 0.6,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            GlassPanel(
              borderRadius: 16,
              tint: panelTint,
              tintOpacity: 0.55,
              blurSigma: 20,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Material(
                color: Colors.transparent,
                child: Column(
                  children: [
                    _ThemeOption(
                      icon: Icons.brightness_auto,
                      label: 'System',
                      subtitle: 'Match your device setting',
                      selected: themeMode == ThemeMode.system,
                      onTap: () => onThemeModeChanged(ThemeMode.system),
                    ),
                    Divider(
                      height: 1,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.08,
                      ),
                    ),
                    _ThemeOption(
                      icon: Icons.light_mode,
                      label: 'Light',
                      selected: themeMode == ThemeMode.light,
                      onTap: () => onThemeModeChanged(ThemeMode.light),
                    ),
                    Divider(
                      height: 1,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.08,
                      ),
                    ),
                    _ThemeOption(
                      icon: Icons.dark_mode,
                      label: 'Dark',
                      selected: themeMode == ThemeMode.dark,
                      onTap: () => onThemeModeChanged(ThemeMode.dark),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'ABOUT',
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 0.6,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            GlassPanel(
              borderRadius: 16,
              tint: panelTint,
              tintOpacity: 0.55,
              blurSigma: 20,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/icon/logonew.png',
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                  ),
                ),
                title: const Text('Shade Map Demo'),
                subtitle: const Text(
                  'Real 3D buildings + computed sun-cast shadows, with a '
                  'standalone sun-path simulator.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.onSurface, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodyLarge),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (selected)
              Icon(
                Icons.check_circle,
                color: theme.colorScheme.primary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
