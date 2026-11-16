import 'package:dawarich/core/data/drift/daos/app_settings_dao.dart';

abstract interface class IAppSettingsLocalDataSource {
  Future<bool> isBiometricLockEnabled(int userId);
  Future<void> setBiometricLockEnabled(int userId, bool enabled);
  Future<int> getLockTimeoutSeconds(int userId);
  Future<void> setLockTimeoutSeconds(int userId, int seconds);
  Future<DateTime?> getLastAuthenticatedAt(int userId);
  Future<void> setLastAuthenticatedAt(int userId, DateTime time);
  Future<String> getThemeMode(int userId);
  Future<void> setThemeMode(int userId, String mode);
  Future<int> getTimelineDistanceThreshold(int userId);
  Future<void> setTimelineDistanceThreshold(int userId, int meters);
}

final class AppSettingsLocalDataSource implements IAppSettingsLocalDataSource {
  final AppSettingsDao _dao;

  AppSettingsLocalDataSource(this._dao);

  @override
  Future<bool> isBiometricLockEnabled(int userId) {
    return _dao.isBiometricLockEnabled(userId);
  }

  @override
  Future<void> setBiometricLockEnabled(int userId, bool enabled) {
    return _dao.setBiometricLockEnabled(userId, enabled);
  }

  @override
  Future<int> getLockTimeoutSeconds(int userId) {
    return _dao.getLockTimeoutSeconds(userId);
  }

  @override
  Future<void> setLockTimeoutSeconds(int userId, int seconds) {
    return _dao.setLockTimeoutSeconds(userId, seconds);
  }

  @override
  Future<DateTime?> getLastAuthenticatedAt(int userId) {
    return _dao.getLastAuthenticatedAt(userId);
  }

  @override
  Future<void> setLastAuthenticatedAt(int userId, DateTime time) {
    return _dao.setLastAuthenticatedAt(userId, time);
  }

  @override
  Future<String> getThemeMode(int userId) {
    return _dao.getThemeMode(userId);
  }

  @override
  Future<void> setThemeMode(int userId, String mode) {
    return _dao.setThemeMode(userId, mode);
  }

  @override
  Future<int> getTimelineDistanceThreshold(int userId) {
    return _dao.getTimelineDistanceThreshold(userId);
  }

  @override
  Future<void> setTimelineDistanceThreshold(int userId, int meters) {
    return _dao.setTimelineDistanceThreshold(userId, meters);
  }
}
