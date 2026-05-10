import 'package:auto_route/annotations.dart';
import 'package:dawarich/core/di/providers/session_providers.dart';
import 'package:dawarich/core/di/providers/settings_providers.dart';
import 'package:dawarich/features/settings/application/usecases/check_biometric_availability_usecase.dart';
import 'package:dawarich/shared/widgets/app_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dawarich/core/shell/drawer/drawer.dart';

@RoutePage()
class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  bool _lockEnabled = false;
  int _lockTimeoutSeconds = 0;
  ThemeMode _themeMode = ThemeMode.system;
  int _distanceThresholdMeters = 50;
  DeviceLockAvailability _availability = const DeviceLockAvailability(
    hasBiometrics: false,
    hasDeviceLock: false,
  );
  bool _loading = true;

  static const _timeoutOptions = <int, String>{
    0: 'Immediately',
    30: '30 seconds',
    60: '1 minute',
    300: '5 minutes',
    600: '10 minutes',
  };

  static const _distanceOptions = <int, String>{
    10: '10 m',
    25: '25 m',
    50: '50 m',
    100: '100 m',
    200: '200 m',
    500: '500 m',
  };

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final isEnabled =
        await ref.read(isBiometricLockEnabledUseCaseProvider.future);
    final getTimeout =
        await ref.read(getLockTimeoutUseCaseProvider.future);
    final getTheme =
        await ref.read(getThemeModeUseCaseProvider.future);
    final getDistance =
        await ref.read(getTimelineDistanceThresholdUseCaseProvider.future);
    final checkAvailability =
        ref.read(checkBiometricAvailabilityUseCaseProvider);
    final userId = ref.read(currentUserIdProvider);

    final enabled = await isEnabled(userId);
    final timeout = await getTimeout(userId);
    final themeStr = await getTheme(userId);
    final distance = await getDistance(userId);
    final availability = await checkAvailability();

    if (mounted) {
      setState(() {
        _lockEnabled = enabled;
        _lockTimeoutSeconds = timeout;
        _themeMode = themeModeFromString(themeStr);
        _distanceThresholdMeters = distance;
        _availability = availability;
        _loading = false;
      });
    }
  }

  Future<void> _onLockToggled(bool value) async {
    final setEnabled =
        await ref.read(setBiometricLockEnabledUseCaseProvider.future);
    final authenticate = ref.read(authenticateBiometricUseCaseProvider);
    final userId = ref.read(currentUserIdProvider);

    if (value) {
      if (!_availability.isAvailable) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'No screen lock is configured on this device.'),
            ),
          );
        }
        return;
      }

      final success = await authenticate(
        reason: 'Verify your identity to enable app lock',
      );

      if (!success) return;
    }

    await setEnabled(userId, enabled: value);
    if (mounted) {
      setState(() => _lockEnabled = value);
    }
  }

  Future<void> _onTimeoutChanged(int seconds) async {
    final setTimeout =
        await ref.read(setLockTimeoutUseCaseProvider.future);
    final userId = ref.read(currentUserIdProvider);

    await setTimeout(userId, seconds: seconds);
    if (mounted) {
      setState(() => _lockTimeoutSeconds = seconds);
    }
  }

  Future<void> _onThemeChanged(ThemeMode mode) async {
    final setTheme =
        await ref.read(setThemeModeUseCaseProvider.future);
    final userId = ref.read(currentUserIdProvider);

    await setTheme(userId, mode: themeModeToString(mode));
    ref.read(themeModeProvider.notifier).set(mode);
    if (mounted) {
      setState(() => _themeMode = mode);
    }
  }

  Future<void> _onDistanceThresholdChanged(int meters) async {
    final setDistance =
        await ref.read(setTimelineDistanceThresholdUseCaseProvider.future);
    final userId = ref.read(currentUserIdProvider);

    await setDistance(userId, meters: meters);
    if (mounted) {
      setState(() => _distanceThresholdMeters = meters);
    }
  }

  String get _lockTitle {
    if (_availability.hasBiometrics) return 'Biometric / Screen Lock';
    if (_availability.hasDeviceLock) return 'Screen Lock (PIN / Pattern)';
    return 'App Lock';
  }

  String get _lockSubtitle {
    if (!_availability.isAvailable) {
      return 'No screen lock is configured on this device';
    }
    if (_availability.hasBiometrics) {
      return 'Use fingerprint, face, or screen lock to open the app';
    }
    return 'Use your PIN or pattern to open the app';
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Settings',
      titleFontSize: 40,
      drawer: const CustomDrawer(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildSettings(context),
    );
  }

  Widget _buildSettings(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // ── General ──
        const _SectionHeader(title: 'General', icon: Icons.tune_outlined),
        const SizedBox(height: 8),
        _SettingsCard(
          children: [
            _PickerTile(
              icon: Icons.palette_outlined,
              title: 'Theme',
              value: themeModeLabel(_themeMode),
              onTap: () => _showThemePicker(context),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // ── Security ──
        const _SectionHeader(title: 'Security', icon: Icons.shield_outlined),
        const SizedBox(height: 8),
        _SettingsCard(
          children: [
            _ToggleTile(
              icon: _availability.hasBiometrics
                  ? Icons.fingerprint
                  : Icons.lock_outline,
              title: _lockTitle,
              subtitle: _lockSubtitle,
              value: _lockEnabled,
              enabled: _availability.isAvailable,
              onChanged: _onLockToggled,
            ),
            if (_lockEnabled) ...[
              _PickerTile(
                icon: Icons.timer_outlined,
                title: 'Lock after',
                value: _timeoutOptions[_lockTimeoutSeconds] ?? 'Immediately',
                onTap: () => _showTimeoutPicker(context),
              ),
            ],
          ],
        ),

        const SizedBox(height: 24),

        // ── Timeline ──
        const _SectionHeader(title: 'Timeline', icon: Icons.map_outlined),
        const SizedBox(height: 8),
        _SettingsCard(
          children: [
            _PickerTile(
              icon: Icons.straighten_outlined,
              title: 'Point merge distance',
              value: _distanceOptions[_distanceThresholdMeters] ??
                  '$_distanceThresholdMeters m',
              onTap: () => _showDistanceThresholdPicker(context),
            ),
          ],
        ),
      ],
    );
  }

  void _showTimeoutPicker(BuildContext context) {
    showModalBottomSheet<int>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Text(
                  'Lock after',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              ..._timeoutOptions.entries.map((e) {
                final isSelected = e.key == _lockTimeoutSeconds;
                return ListTile(
                  title: Text(e.value),
                  trailing:
                      isSelected ? Icon(Icons.check, color: theme.colorScheme.primary) : null,
                  onTap: () => Navigator.pop(ctx, e.key),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    ).then((selected) {
      if (selected != null) {
        _onTimeoutChanged(selected);
      }
    });
  }

  void _showThemePicker(BuildContext context) {    showModalBottomSheet<ThemeMode>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Text(
                  'Theme',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              for (final mode in ThemeMode.values)
                ListTile(
                  leading: Icon(_themeIcon(mode),
                      color: mode == _themeMode
                          ? theme.colorScheme.primary
                          : null),
                  title: Text(themeModeLabel(mode)),
                  trailing: mode == _themeMode
                      ? Icon(Icons.check, color: theme.colorScheme.primary)
                      : null,
                  onTap: () => Navigator.pop(ctx, mode),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    ).then((selected) {
      if (selected != null) {
        _onThemeChanged(selected);
      }
    });
  }

  IconData _themeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode_outlined;
      case ThemeMode.dark:
        return Icons.dark_mode_outlined;
      case ThemeMode.system:
        return Icons.brightness_auto_outlined;
    }
  }

  void _showDistanceThresholdPicker(BuildContext context) {
    showModalBottomSheet<int>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Point merge distance',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Consecutive points closer than this threshold are '
                      'merged on the timeline.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color
                            ?.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              ..._distanceOptions.entries.map((e) {
                final isSelected = e.key == _distanceThresholdMeters;
                return ListTile(
                  title: Text(e.value),
                  trailing: isSelected
                      ? Icon(Icons.check, color: theme.colorScheme.primary)
                      : null,
                  onTap: () => Navigator.pop(ctx, e.key),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    ).then((selected) {
      if (selected != null) {
        _onDistanceThresholdChanged(selected);
      }
    });
  }
}

// ---------------------------------------------------------------------------
// Reusable settings widgets
// ---------------------------------------------------------------------------

final class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

final class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black)
            .withValues(alpha: isDark ? 0.07 : 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black)
              .withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(
                height: 1,
                indent: 56,
                color: (isDark ? Colors.white : Colors.black)
                    .withValues(alpha: 0.06),
              ),
          ],
        ],
      ),
    );
  }
}

final class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(
            icon,
            size: 24,
            color: enabled ? theme.colorScheme.primary : theme.disabledColor,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color
                        ?.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: value,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}

final class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 24, color: theme.colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color
                        ?.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: theme.iconTheme.color?.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }
}

final class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  const _PickerTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 24, color: theme.colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
            Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: theme.iconTheme.color?.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}
