import 'dart:ui';
import 'package:auto_route/auto_route.dart';
import 'package:dawarich/core/di/providers/core_providers.dart';
import 'package:dawarich/core/di/providers/drawer_providers.dart';
import 'package:dawarich/core/shell/drawer/drawer_viewmodel.dart';
import 'package:dawarich/core/theme/app_gradients.dart';
import 'package:dawarich/features/version_check/domain/server_compatibility_status.dart';
import 'package:dawarich/features/version_check/domain/server_compatibility_state.dart';
import 'package:dawarich/features/version_check/presentation/server_compatibility_providers.dart';
import 'package:flutter/material.dart';
import 'package:dawarich/core/routing/app_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

final class CustomDrawer extends ConsumerStatefulWidget {
  const CustomDrawer({super.key});

  @override
  ConsumerState<CustomDrawer> createState() => _CustomDrawerState();
}

class _CustomDrawerState extends ConsumerState<CustomDrawer> {
  bool _isNavigating = false;

  @override
  Widget build(BuildContext context) {
    final vmAsync = ref.watch(drawerViewModelProvider);

    return vmAsync.when(
      loading: () => _buildDrawerShell(
        context,
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => _buildDrawerShell(
        context,
        child: Center(child: Text(e.toString())),
      ),
      data: (vm) => _DrawerBody(
        vm: vm,
        ref: ref,
        onNavigate: (route) => _navigateTo(context, route),
        onLogout: () => _logout(context, vm),
        onAbout: () => _pushTo(context, const AboutRoute()),
      ),
    );
  }

  Widget _buildDrawerShell(BuildContext context, {required Widget child}) {
    return SafeArea(
      child: Drawer(
        backgroundColor: Colors.transparent,
        width: MediaQuery.of(context).size.width * 0.78,
        child: ClipRRect(
          borderRadius:
              const BorderRadius.horizontal(right: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration:
                  BoxDecoration(gradient: Theme.of(context).pageBackground),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  void _closeDrawer(BuildContext context) {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  void _runNavGuarded(Future<void> Function() action) {
    if (_isNavigating) {
      return;
    }
    _isNavigating = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await action();
      } finally {
        _isNavigating = false;
      }
    });
  }

  Future<void> _navigateTo(
      BuildContext context, PageRouteInfo<Object?> route) async {
    final router = context.router.root;
    _runNavGuarded(() async {
      if (!mounted) {
        return;
      }
      _closeDrawer(context);
      await router.replace(route);
    });
  }

  Future<void> _pushTo(
      BuildContext context, PageRouteInfo<Object?> route) async {
    final router = context.router.root;
    _runNavGuarded(() async {
      if (!mounted) {
        return;
      }
      _closeDrawer(context);
      await router.push(route);
    });
  }

  Future<void> _logout(BuildContext context, DrawerViewModel vm) async {
    final router = context.router.root;
    _runNavGuarded(() async {
      if (!mounted) {
        return;
      }
      _closeDrawer(context);
      await vm.logout();
      if (!mounted) {
        return;
      }
      router.replaceAll([const AuthRoute()]);
    });
  }
}

// Drawer body

final class _DrawerBody extends StatelessWidget {
  final DrawerViewModel vm;
  final WidgetRef ref;
  final void Function(PageRouteInfo<Object?> route) onNavigate;
  final VoidCallback onLogout;
  final VoidCallback onAbout;

  const _DrawerBody({
    required this.vm,
    required this.ref,
    required this.onNavigate,
    required this.onLogout,
    required this.onAbout,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: Drawer(
        backgroundColor: Colors.transparent,
        width: MediaQuery.of(context).size.width * 0.78,
        child: ClipRRect(
          borderRadius:
              const BorderRadius.horizontal(right: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                gradient: theme.pageBackground,
                border: Border(
                  right: BorderSide(
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.06),
                  ),
                ),
              ),
              child: Column(
                children: [
                  _DrawerHeader(ref: ref),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _NavSection(onNavigate: onNavigate),
                  ),
                  _BottomSection(
                    onLogout: onLogout,
                    onAbout: onAbout,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Header

final class _DrawerHeader extends StatelessWidget {
  final WidgetRef ref;

  const _DrawerHeader({required this.ref});

  void _showCompatibilityDialog(
    BuildContext context,
    ServerCompatibilityState compatState,
  ) {    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final (IconData icon, Color color, String statusLabel) =
        switch (compatState.status) {
      ServerCompatibilityStatus.ok => (
          Icons.check_circle,
          Colors.green,
          'Compatible',
        ),
      ServerCompatibilityStatus.warning => (
          Icons.warning_amber_rounded,
          Colors.orange,
          'Warning',
        ),
      ServerCompatibilityStatus.incompatible => (
          Icons.error_outline,
          Colors.red,
          'Incompatible',
        ),
      ServerCompatibilityStatus.unknown => (
          Icons.help_outline,
          Colors.grey,
          'Unknown',
        ),
    };

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Text(
              'Server Compatibility',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow(label: 'Status', value: statusLabel, color: color),
            if (compatState.serverVersion != null)
              _InfoRow(
                label: 'Server',
                value: 'v${compatState.serverVersion}',
              ),
            if (compatState.appVersion != null)
              _InfoRow(
                label: 'App',
                value: 'v${compatState.appVersion}',
              ),
            if (compatState.recommendServer != null)
              _InfoRow(
                label: 'Recommended server',
                value: compatState.recommendServer!,
              ),
            if (compatState.message != null) ...[
              const SizedBox(height: 12),
              Text(
                compatState.message!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color
                      ?.withValues(alpha: isDark ? 0.75 : 0.8),
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final compatState = ref.watch(serverCompatibilityProvider);
    final apiCfgAsync = ref.watch(apiConfigManagerProvider);

    final String? serverHost = apiCfgAsync.whenOrNull(
      data: (cfg) {
        final host = cfg.apiConfig?.host;
        if (host == null || host.isEmpty) return null;
        // Strip protocol for a cleaner display
        return host
            .replaceFirst(RegExp(r'^https?://'), '')
            .replaceFirst(RegExp(r'/$'), '');
      },
    );

    final String? serverVersion = compatState.serverVersion;
    final ServerCompatibilityStatus status = compatState.status;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 44, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // App title
          Row(            children: [
              Icon(Icons.pin_drop, size: 28, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                'Dawarich',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Server info pill
          GestureDetector(
            onTap: () => _showCompatibilityDialog(context, compatState),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: (isDark ? Colors.white : Colors.black)
                    .withValues(alpha: isDark ? 0.07 : 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (isDark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.06),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.dns_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          serverHost ?? 'Not connected',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        if (serverVersion != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Server v$serverVersion',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: theme.textTheme.bodySmall?.color
                                  ?.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _CompatBadge(status: status),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Compatibility badge

final class _CompatBadge extends StatelessWidget {
  final ServerCompatibilityStatus status;

  const _CompatBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String tooltip) = switch (status) {
      ServerCompatibilityStatus.ok => (
          Icons.check_circle,
          Colors.green,
          'Compatible',
        ),
      ServerCompatibilityStatus.warning => (
          Icons.warning_amber_rounded,
          Colors.orange,
          'Compatibility warning',
        ),
      ServerCompatibilityStatus.incompatible => (
          Icons.error_outline,
          Colors.red,
          'Incompatible',
        ),
      ServerCompatibilityStatus.unknown => (
          Icons.help_outline,
          Colors.grey,
          'Status unknown',
        ),
    };

    return Tooltip(
      message: tooltip,
      child: Icon(icon, size: 20, color: color),
    );
  }
}

// Navigation section

final class _NavSection extends StatelessWidget {
  final void Function(PageRouteInfo<Object?> route) onNavigate;

  const _NavSection({required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      children: [
        _NavTile(
          icon: Icons.map_outlined,
          label: 'Timeline',
          onTap: () => onNavigate(const TimelineRoute()),
        ),
        const SizedBox(height: 8),
        _NavTile(
          icon: Icons.analytics_outlined,
          label: 'Stats',
          onTap: () => onNavigate(const StatsRoute()),
        ),
        const SizedBox(height: 8),
        _NavTile(
          icon: Icons.place_outlined,
          label: 'Points',
          onTap: () => onNavigate(const PointsRoute()),
        ),
        const SizedBox(height: 8),
        _NavTile(
          icon: Icons.gps_fixed_outlined,
          label: 'Tracker',
          onTap: () => onNavigate(const TrackerRoute()),
        ),
        const SizedBox(height: 8),
        _NavTile(
          icon: Icons.settings_outlined,
          label: 'Settings',
          onTap: () => onNavigate(const SettingsRoute()),
        ),
      ],
    );
  }
}

final class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: (isDark ? Colors.white : Colors.black)
          .withValues(alpha: isDark ? 0.07 : 0.04),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: theme.colorScheme.primary.withValues(alpha: 0.10),
        highlightColor: theme.colorScheme.primary.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Icon(
                icon,
                size: 26,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 16),
              Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Bottom section

final class _BottomSection extends StatelessWidget {
  final VoidCallback onLogout;
  final VoidCallback onAbout;

  const _BottomSection({
    required this.onLogout,
    required this.onAbout,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
          thickness: 1,
          height: 1,
          indent: 24,
          endIndent: 24,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: onLogout,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded,
                        size: 22, color: Colors.red.shade300),
                    const SizedBox(width: 16),
                    Text(
                      'Logout',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                        color: Colors.red.shade300,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Version badge
        GestureDetector(
          onTap: onAbout,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
            child: FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final version =
                    snapshot.hasData ? 'v${snapshot.data!.version}' : '';
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: isDark ? 0.07 : 0.04),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: (isDark ? Colors.white : Colors.black)
                          .withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 13,
                        color: theme.textTheme.bodySmall?.color
                            ?.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Dawarich $version',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color
                              ?.withValues(alpha: 0.5),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

}

// Shared helpers

/// A compact label/value row used inside the compatibility dialog.
final class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _InfoRow({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.55),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

}
