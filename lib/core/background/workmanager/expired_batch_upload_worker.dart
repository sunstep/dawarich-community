
import 'package:dawarich/core/di/providers/core_providers.dart';
import 'package:dawarich/core/di/providers/session_providers.dart';
import 'package:dawarich/core/di/providers/usecase_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:option_result/result.dart';
import 'package:workmanager/workmanager.dart';

final class ExpiredBatchUploadWorker {
  static const String uniqueWorkName = 'expired-batch-upload-check';

  @pragma('vm:entry-point')
  static void callbackDispatcher() {
    Workmanager().executeTask((task, inputData) async {
      if (task != uniqueWorkName) {
        return true;
      }

      ProviderContainer? container;

      try {
        if (kDebugMode) {
          debugPrint('[ExpiredBatchWorker] Starting worker...');
        }

        container = ProviderContainer();
        await container.read(coreProvider.future);

        final session = await container.read(sessionBoxProvider.future);
        final user = await session.refreshSession();

        if (user == null) {
          if (kDebugMode) {
            debugPrint('[ExpiredBatchWorker] No user session, skipping.');
          }
          return true;
        }

        final checkExpiredBatch =
        await container.read(checkAndUploadExpiredBatchUseCaseProvider.future);

        final result = await checkExpiredBatch(user.id);

        if (result case Ok(value: final didUpload)) {
          if (kDebugMode) {
            if (didUpload) {
              debugPrint('[ExpiredBatchWorker] Expired batch uploaded.');
            } else {
              debugPrint('[ExpiredBatchWorker] No expired batch to upload.');
            }
          }
        } else if (result case Err(value: final err)) {
          debugPrint('[ExpiredBatchWorker] Expired batch check failed: $err');
        }

        return true;
      } catch (e, s) {
        debugPrint('[ExpiredBatchWorker] Fatal worker error: $e\n$s');

        // This is an opportunistic check, not a mission-critical exact job.
        // Returning true avoids retry storms.
        return true;
      } finally {
        container?.dispose();
      }
    });
  }
}