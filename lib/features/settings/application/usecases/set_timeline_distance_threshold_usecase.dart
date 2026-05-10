import 'package:dawarich/features/settings/application/repositories/app_settings_repository_interfaces.dart';

final class SetTimelineDistanceThresholdUseCase {
  final IAppSettingsRepository _repository;

  SetTimelineDistanceThresholdUseCase(this._repository);

  /// Persists the minimum distance in metres between consecutive timeline
  /// points.  Must be >= 1.
  Future<void> call(int userId, {required int meters}) {
    assert(meters >= 1, 'distance threshold must be at least 1 m');
    return _repository.setTimelineDistanceThreshold(userId, meters);
  }
}

