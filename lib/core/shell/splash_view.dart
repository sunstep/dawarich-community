import 'dart:async';

import 'package:auto_route/annotations.dart';
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

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugPrint('[SplashPage] initState called');
    }
    _startBoot();
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
        const Duration(seconds: 10),
        onTimeout: () {
          if (kDebugMode) {
            debugPrint('[SplashPage] Core provider timed out');
          }
          throw TimeoutException('Core provider initialization timed out');
        },
      );

      if (!mounted) return;

      if (kDebugMode) {
        debugPrint('[SplashPage] coreProvider initialized successfully');
      }

      final container = ProviderScope.containerOf(context);

      // Guard the full startup sequence with its own timeout.
      // coreProvider.timeout(10s) only covers DB/API/network init.
      // initializeAppFromContainer does additional work (WorkManager, session,
      // permissions) any of which could block on a platform-channel call.
      // Without this guard, the splash screen can stall indefinitely.
      await StartupService.initializeAppFromContainer(container).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          if (kDebugMode) {
            debugPrint('[SplashPage] StartupService timed out after 30s');
          }
          throw TimeoutException('App startup timed out');
        },
      );

      if (kDebugMode) {
        debugPrint('[SplashPage] Boot completed.');
      }
    } on TimeoutException {
      if (!_hasRetriedAfterTimeout) {
        _hasRetriedAfterTimeout = true;
        if (kDebugMode) {
          debugPrint('[SplashPage] Timeout - invalidating providers and retrying...');
        }

        ref.invalidate(coreProvider);
        _hasStartedBoot = false;
        await Future.delayed(const Duration(milliseconds: 1000));
        await _startBoot();
        return;
      }

      if (kDebugMode) {
        debugPrint('[SplashPage] Second timeout - navigating to auth');
      }
      if (mounted) {
        appRouter.replaceAll([const AuthRoute()]);
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[SplashPage] Error during boot: $e\n$st');
      }
      if (mounted) {
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