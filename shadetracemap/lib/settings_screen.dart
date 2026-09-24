import 'package:flutter/material.dart';

import 'app_style.dart';
import 'glass_panel.dart';

const _accent = Color(0xFFFFB300);

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
    final labelColor = theme.colorScheme.onSurfaceVariant;

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
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          children: [
            Text(
              'Settings',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 20),
            GlassPanel(
              borderRadius: kCardRadius,
              tint: panelTint,
              tintOpacity: 0.55,
              blurSigma: 20,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/icon/logonew.png',
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Shade Map Demo',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Real 3D buildings + computed sun-cast shadows, '
                          'with a standalone sun-path simulator.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: labelColor,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: SectionLabel('APPEARANCE', color: labelColor),
            ),
            GlassPanel(
              borderRadius: kCardRadius,
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
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: SectionLabel('ABOUT', color: labelColor),
            ),
            GlassPanel(
              borderRadius: kCardRadius,
              tint: panelTint,
              tintOpacity: 0.55,
              blurSigma: 20,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  _InfoRow(
                    icon: Icons.info_outline,
                    label: 'Version',
                    value: '1.2.0',
                  ),
                  Divider(
                    height: 1,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                  ),
                  _InfoRow(
                    icon: Icons.favorite_border,
                    label: 'Made for sun-chasers',
                    value: '☀️',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 15, color: _accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
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
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (selected ? _accent : theme.colorScheme.onSurface)
                    .withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: selected ? _accent : theme.colorScheme.onSurface,
                size: 18,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
              Icon(Icons.check_circle, color: _accent, size: 20),
          ],
        ),
      ),
    );
  }
}
