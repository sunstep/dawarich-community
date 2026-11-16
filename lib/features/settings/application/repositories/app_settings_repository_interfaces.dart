abstract interface class IAppSettingsRepository {
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
