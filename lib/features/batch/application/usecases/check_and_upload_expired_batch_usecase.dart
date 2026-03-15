
import 'package:dawarich/core/data/repositories/local_point_repository_interfaces.dart';
import 'package:dawarich/features/batch/application/usecases/batch_upload_workflow_usecase.dart';
import 'package:dawarich/features/batch/application/usecases/get_current_batch_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/settings/get_tracker_settings_usecase.dart';
import 'package:option_result/result.dart';

final class CheckAndUploadExpiredBatchUseCase {
  final GetTrackerSettingsUseCase _getTrackerSettings;
  final IPointLocalRepository _localPointRepository;
  final GetCurrentBatchUseCase _getCurrentBatch;
  final BatchUploadWorkflowUseCase _batchUploadWorkflow;

  CheckAndUploadExpiredBatchUseCase(
      this._getTrackerSettings,
      this._localPointRepository,
      this._getCurrentBatch,
      this._batchUploadWorkflow,
      );

  Future<Result<bool, String>> call(int userId) async {
    try {
      final settings = await _getTrackerSettings(userId);

      if (!settings.isBatchExpirationEnabled ||
          settings.batchExpirationMinutes == null) {
        return const Ok(false);
      }

      final oldest =
      await _localPointRepository.getOldestUnUploadedPointTimestamp(userId);

      if (oldest == null) {
        return const Ok(false);
      }

      final threshold = DateTime.now().subtract(
        Duration(minutes: settings.batchExpirationMinutes!),
      );

      if (!oldest.isBefore(threshold)) {
        return const Ok(false);
      }

      final batch = await _getCurrentBatch(userId);
      if (batch.isEmpty) {
        return const Ok(false);
      }

      final uploadResult = await _batchUploadWorkflow(batch, userId);

      if (uploadResult case Ok()) {
        return const Ok(true);
      }

      if (uploadResult case Err(value: final err)) {
        return Err(err);
      }

      return const Err('Unknown upload result');
    } catch (e) {
      return Err('Failed to check expired batch: $e');
    }
  }
}