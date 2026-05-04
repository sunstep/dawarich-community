import 'dart:async';

import 'package:auto_route/annotations.dart';
import 'package:dawarich/core/data/drift/database/sqlite_client.dart';
import 'package:dawarich/core/di/providers/core_providers.dart';
import 'package:dawarich/core/routing/app_router.dart';
import 'package:dawarich/core/startup/startup_service.dart';
import 'package:dawarich/core/theme/app_gradients.dart';
import 'package:dawarich/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@RoutePage()
class SplashView extends ConsumerStatefulWidget {
  const SplashView({super.key});

  @override
  ConsumerState<SplashView> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashView> {
  bool _hasStartedBoot = false;
  bool _hasRetriedAfterTimeout = false;
  bool _hasNavigatedAway = false;
  Timer? _escapeTimer;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugPrint('[SplashPage] initState called');
    }

    _escapeTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && !_hasNavigatedAway) {
        _hasNavigatedAway = true;
        if (kDebugMode) {
          debugPrint('[SplashPage] Hard escape timer fired — navigating to auth');
        }
        appRouter.replaceAll([const AuthRoute()]);
      }
    });

    _startBoot();
  }

  @override
  void dispose() {
    _escapeTimer?.cancel();
    super.dispose();
  }

  Future<void> _startBoot() async {
    if (_hasStartedBoot) return;
    _hasStartedBoot = true;

    if (kDebugMode) {
      debugPrint('[SplashPage] Starting boot...');
    }


    try {
      if (kDebugMode) {
        debugPrint('[SplashPage] Reading coreProvider...');
      }

      await ref.read(coreProvider.future).timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          if (kDebugMode) {
            debugPrint('[SplashPage] Core provider timed out');
          }
          throw TimeoutException('Core provider initialization timed out');
        },
      );

      if (!mounted || _hasNavigatedAway) return;

      if (kDebugMode) {
        debugPrint('[SplashPage] coreProvider initialized successfully');
      }

      final container = ProviderScope.containerOf(context);

      await StartupService.initializeAppFromContainer(container).timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          if (kDebugMode) {
            debugPrint('[SplashPage] StartupService timed out after 12s');
          }
          throw TimeoutException('App startup timed out');
        },
      );

      if (!mounted || _hasNavigatedAway) return;

      _hasNavigatedAway = true;
      _escapeTimer?.cancel();

      if (kDebugMode) {
        debugPrint('[SplashPage] Boot completed.');
      }
    } on TimeoutException {
      if (_hasNavigatedAway) return;

      if (!_hasRetriedAfterTimeout) {
        _hasRetriedAfterTimeout = true;
        if (kDebugMode) {
          debugPrint('[SplashPage] Timeout - invalidating providers and retrying...');
        }

        // Clear stale Drift IsolateNameServer mapping and cached instance
        // so the retry doesn't re-watch the same stuck future. This is
        // critical when the background service's Drift isolate is busy —
        // without this, the retry re-watches sqliteClientProvider which
        // is still awaiting the old (timed-out) connectSharedIsolate().
        SQLiteClient.resetSharedState();
        ref.invalidate(sqliteClientProvider);
        ref.invalidate(coreProvider);
        _hasStartedBoot = false;
        await Future.delayed(const Duration(milliseconds: 500));
        if (_hasNavigatedAway) return;
        await _startBoot();
        return;
      }

      if (kDebugMode) {
        debugPrint('[SplashPage] Second timeout - navigating to auth');
      }
      if (mounted && !_hasNavigatedAway) {
        _hasNavigatedAway = true;
        _escapeTimer?.cancel();
        appRouter.replaceAll([const AuthRoute()]);
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[SplashPage] Error during boot: $e\n$st');
      }
      if (mounted && !_hasNavigatedAway) {
        _hasNavigatedAway = true;
        _escapeTimer?.cancel();
        appRouter.replaceAll([const AuthRoute()]);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: Theme.of(context).pageBackground),
      child: const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 24),
              Text('Loading...'),
            ],
          ),
        ),
      ),
    );
  }


}