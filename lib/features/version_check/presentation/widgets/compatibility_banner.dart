import 'package:dawarich/features/version_check/domain/server_compatibility_status.dart';
import 'package:dawarich/features/version_check/presentation/server_compatibility_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dawarich/features/version_check/domain/server_compatibility_state.dart';

/// A banner that warns the user when their server/app combination
/// has compatibility issues.  Renders nothing when everything is OK.
final class CompatibilityBanner extends ConsumerStatefulWidget {
  const CompatibilityBanner({super.key});

  @override
  ConsumerState<CompatibilityBanner> createState() =>
      _CompatibilityBannerState();
}

class _CompatibilityBannerState extends ConsumerState<CompatibilityBanner>
    with SingleTickerProviderStateMixin {
  bool _dismissed = false;
  bool _prefsLoaded = false;
  String? _persistedDismissedKey;

  late final AnimationController _animController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  static const String _prefKey = 'compat_banner_dismissed_key';

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _persistedDismissedKey = prefs.getString(_prefKey);
      _prefsLoaded = true;
    });
  }

  String _keyForState(ServerCompatibilityState state) =>
      '${state.serverVersion ?? "unknown"}_${state.status.name}';

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    final state = ref.read(serverCompatibilityProvider);
    final key = _keyForState(state);

    await _animController.reverse();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, key);

    if (mounted) {
      setState(() {
        _dismissed = true;
        _persistedDismissedKey = key;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) {
      return const SizedBox.shrink();
    }

    final state = ref.watch(serverCompatibilityProvider);
    if (!state.shouldWarn) {
      return const SizedBox.shrink();
    }

    if (!_prefsLoaded) {
      return const SizedBox.shrink();
    }

    final currentKey = _keyForState(state);
    if (currentKey == _persistedDismissedKey) {
      return const SizedBox.shrink();
    }

    if (_animController.status == AnimationStatus.dismissed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _animController.forward();
      });
    }

    final bool isIncompatible =
        state.status == ServerCompatibilityStatus.incompatible;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final Color accentColor = isIncompatible
        ? (isDark ? Colors.redAccent : Colors.red.shade600)
        : (isDark ? Colors.orangeAccent : Colors.orange.shade700);

    final Color cardColor = isDark
        ? (isIncompatible
            ? const Color(0xFF2C1616)
            : const Color(0xFF2C2416))
        : (isIncompatible ? Colors.red.shade50 : Colors.orange.shade50);

    final Color borderColor = accentColor.withValues(alpha: isDark ? 0.4 : 0.3);

    final Color textColor = isDark
        ? Colors.white.withValues(alpha: 0.87)
        : (isIncompatible ? Colors.red.shade900 : Colors.orange.shade900);

    final Color subtitleColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : (isIncompatible ? Colors.red.shade700 : Colors.orange.shade800);

    final String title =
        isIncompatible ? 'Server Incompatible' : 'Compatibility Warning';
    final String message =
        state.message ?? 'Server compatibility issue detected.';

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 1),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: isDark ? 0.15 : 0.10),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Icon badge ──
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: isDark ? 0.20 : 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isIncompatible
                          ? Icons.error_outline_rounded
                          : Icons.warning_amber_rounded,
                      color: accentColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: textColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          message,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: subtitleColor,
                                    height: 1.35,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  GestureDetector(
                    onTap: _dismiss,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: textColor.withValues(alpha: 0.5),
                      ),
                    ),
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

