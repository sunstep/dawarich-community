import 'package:dawarich/core/background/workmanager/app_workmanager.dart';
import 'package:dawarich/core/background/workmanager/tracker_watchdog_worker.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

final class TrackingWatchdogWorkScheduler {
  static Future<void> register() async {
    await ensureWorkmanagerInitialized();

    if (kDebugMode) {
      debugPrint('[TrackingWatchdog] Registering periodic watchdog.');
    }

    await Workmanager().registerPeriodicTask(
      TrackingWatchdogWorker.uniqueWorkName,
      TrackingWatchdogWorker.uniqueWorkName,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  static Future<void> cancel() async {
    await ensureWorkmanagerInitialized();

    if (kDebugMode) {
      debugPrint('[TrackingWatchdog] Cancelling periodic watchdog.');
    }

    await Workmanager().cancelByUniqueName(
      TrackingWatchdogWorker.uniqueWorkName,
    );
  }
}