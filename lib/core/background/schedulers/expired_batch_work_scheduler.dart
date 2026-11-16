
import 'package:dawarich/core/background/workmanager/expired_batch_upload_worker.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

final class ExpiredBatchWorkScheduler {
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    await Workmanager().initialize(
      ExpiredBatchUploadWorker.callbackDispatcher,
    );

    _initialized = true;
  }

  static Future<void> register(int expirationMinutes) async {
    await initialize();

    final frequency = _getWorkerFrequency(expirationMinutes);

    if (kDebugMode) {
      debugPrint(
        '[ExpiredBatchWorker] Registering periodic work every '
            '${frequency.inMinutes} minutes.',
      );
    }

    await Workmanager().registerPeriodicTask(
      ExpiredBatchUploadWorker.uniqueWorkName,
      ExpiredBatchUploadWorker.uniqueWorkName,
      frequency: frequency,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }

  static Future<void> cancel() async {
    await initialize();

    if (kDebugMode) {
      debugPrint('[ExpiredBatchWorker] Cancelling periodic work.');
    }

    await Workmanager().cancelByUniqueName(
      ExpiredBatchUploadWorker.uniqueWorkName,
    );
  }

  static Duration _getWorkerFrequency(int expirationMinutes) {
    final minutes = expirationMinutes < 15 ? 15 : expirationMinutes;
    return Duration(minutes: minutes);
  }
}