import 'package:auto_route/auto_route.dart';
import 'package:dawarich/core/di/providers/session_providers.dart';
import 'package:dawarich/core/di/providers/settings_providers.dart';
import 'package:dawarich/core/routing/app_router.dart';
import 'package:dawarich/core/theme/app_gradients.dart';
import 'package:dawarich/features/onboarding/application/usecases/check_onboarding_permissions_usecase.dart';
import 'package:dawarich/features/onboarding/application/usecases/request_onboarding_permission_usecase.dart';
import 'package:dawarich/features/onboarding/domain/permission_item.dart';
import 'package:dawarich/features/onboarding/presentation/viewmodels/permissions_onboarding_viewmodel.dart';
import 'package:dawarich/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as legacy;

@RoutePage()
final class PermissionsOnboardingView extends ConsumerStatefulWidget {
  const PermissionsOnboardingView({super.key});

  @override
  ConsumerState<PermissionsOnboardingView> createState() =>
      _PermissionsOnboardingViewState();
}

class _PermissionsOnboardingViewState
    extends ConsumerState<PermissionsOnboardingView>
    with WidgetsBindingObserver {
  late final PermissionsOnboardingViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = PermissionsOnboardingViewModel(
      CheckOnboardingPermissionsUseCase(),
      RequestOnboardingPermissionUseCase(),
    );
    _vm.initialize();
    _vm.addListener(_onVmChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _vm.removeListener(_onVmChanged);
    _vm.dispose();
    super.dispose();
  }

  /// When the user returns from system settings (e.g. battery optimization),
  /// re-check all permissions.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _vm.refreshPermissions();
    }
  }

  void _onVmChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _onContinue() async {
    try {
      final isEnabled =
          await ref.read(isBiometricLockEnabledUseCaseProvider.future);
      final userId = await ref.read(sessionUserIdProvider.future);
      final biometricEnabled = userId != null && await isEnabled(userId);
      if (biometricEnabled) {
        appRouter.replaceAll([const BiometricLockRoute()]);
      } else {
        appRouter.replaceAll([const TimelineRoute()]);
      }
    } catch (_) {
      // Providers not yet ready or some other error — go straight to timeline.
      appRouter.replaceAll([const TimelineRoute()]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return legacy.ChangeNotifierProvider<PermissionsOnboardingViewModel>.value(
      value: _vm,
      child: Container(
        decoration: BoxDecoration(gradient: Theme.of(context).pageBackground),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: _vm.isLoading
                ? const Center(child: CircularProgressIndicator())
                : _PermissionsContent(
                    vm: _vm,
                    onContinue: _onContinue,
                  ),
          ),
        ),
      ),
    );
  }
}

final class _PermissionsContent extends StatelessWidget {
  final PermissionsOnboardingViewModel vm;
  final VoidCallback onContinue;

  const _PermissionsContent({
    required this.vm,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Card(
          elevation: 12,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header ──
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primary,
                  radius: 36,
                  child: Icon(
                    vm.allGranted ? Icons.check_circle : Icons.shield_outlined,
                    size: 36,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'One last step!',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Dawarich needs a few permissions to track your location reliably in the background.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
                const SizedBox(height: 28),

                // ── Permission tiles ──
                ...List.generate(vm.permissions.length, (i) {
                  final item = vm.permissions[i];
                  return _PermissionTile(
                    item: item,
                    onRequest: vm.isRequesting
                        ? null
                        : () => vm.requestPermission(i),
                  );
                }),

                const SizedBox(height: 24),

                // ── Progress indicator ──
                _ProgressRow(
                  granted: vm.grantedCount,
                  total: vm.permissions.length,
                ),

                const SizedBox(height: 20),

                // ── Continue / Skip button ──
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onContinue,
                    child: Text(vm.allGranted ? 'Continue' : 'Skip'),
                  ),
                ),
                if (!vm.allGranted) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Some features (background tracking) require these permissions.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color
                          ?.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _PermissionTile extends StatelessWidget {
  final PermissionItem item;
  final VoidCallback? onRequest;

  const _PermissionTile({
    required this.item,
    required this.onRequest,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final bool granted = item.granted;

    final Color tileColor = granted
        ? (isDark ? const Color(0xFF1B2E1B) : Colors.green.shade50)
        : (isDark ? theme.colorScheme.surface : Colors.grey.shade50);

    final Color iconColor = granted
        ? (isDark ? Colors.greenAccent : Colors.green.shade600)
        : theme.iconTheme.color ?? Colors.grey;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: tileColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: granted ? null : onRequest,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  granted ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: iconColor,
                  size: 26,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!granted) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right,
                    color: theme.iconTheme.color?.withValues(alpha: 0.5),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _ProgressRow extends StatelessWidget {
  final int granted;
  final int total;

  const _ProgressRow({required this.granted, required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final double progress = total > 0 ? granted / total : 0;

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: theme.brightness == Brightness.dark
                ? Colors.white12
                : Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(
              granted == total ? Colors.green : theme.colorScheme.secondary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '$granted of $total permissions granted',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

