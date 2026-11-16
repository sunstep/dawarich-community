import 'package:dawarich/features/settings/application/repositories/app_settings_repository_interfaces.dart';

final class GetTimelineDistanceThresholdUseCase {
  final IAppSettingsRepository _repository;

  GetTimelineDistanceThresholdUseCase(this._repository);

  /// Returns the minimum distance in metres between consecutive timeline
  /// points.  Defaults to 50 m (the previous hard-coded value).
  Future<int> call(int userId) {
    return _repository.getTimelineDistanceThreshold(userId);
  }
}

