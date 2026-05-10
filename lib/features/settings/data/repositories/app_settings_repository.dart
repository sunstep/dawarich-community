import 'package:dawarich/features/settings/application/repositories/app_settings_repository_interfaces.dart';
import 'package:dawarich/features/settings/data/sources/local/app_settings_local_data_source.dart';

final class AppSettingsRepository implements IAppSettingsRepository {
  final IAppSettingsLocalDataSource _local;

  AppSettingsRepository(this._local);

  @override
  Future<bool> isBiometricLockEnabled(int userId) {
    return _local.isBiometricLockEnabled(userId);
  }

  @override
  Future<void> setBiometricLockEnabled(int userId, bool enabled) {
    return _local.setBiometricLockEnabled(userId, enabled);
  }

  @override
  Future<int> getLockTimeoutSeconds(int userId) {
    return _local.getLockTimeoutSeconds(userId);
  }

  @override
  Future<void> setLockTimeoutSeconds(int userId, int seconds) {
    return _local.setLockTimeoutSeconds(userId, seconds);
  }

  @override
  Future<DateTime?> getLastAuthenticatedAt(int userId) {
    return _local.getLastAuthenticatedAt(userId);
  }

  @override
  Future<void> setLastAuthenticatedAt(int userId, DateTime time) {
    return _local.setLastAuthenticatedAt(userId, time);
  }

  @override
  Future<String> getThemeMode(int userId) {
    return _local.getThemeMode(userId);
  }

  @override
  Future<void> setThemeMode(int userId, String mode) {
    return _local.setThemeMode(userId, mode);
  }

  @override
  Future<int> getTimelineDistanceThreshold(int userId) {
    return _local.getTimelineDistanceThreshold(userId);
  }

  @override
  Future<void> setTimelineDistanceThreshold(int userId, int meters) {
    return _local.setTimelineDistanceThreshold(userId, meters);
  }
}
