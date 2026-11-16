import 'package:dawarich/core/data/drift/database/sqlite_client.dart';
import 'package:dawarich/core/data/drift/entities/settings/app_settings_table.dart';
import 'package:drift/drift.dart';

part 'app_settings_dao.g.dart';

@DriftAccessor(tables: [AppSettingsTable])
class AppSettingsDao extends DatabaseAccessor<SQLiteClient>
    with _$AppSettingsDaoMixin {
  AppSettingsDao(super.db);

  Future<AppSettingsTableData?> getSettings(int userId) async {
    final query = select(db.appSettingsTable)
      ..where((t) => t.userId.equals(userId));
    return query.getSingleOrNull();
  }

  Future<bool> isBiometricLockEnabled(int userId) async {
    final row = await getSettings(userId);
    return row?.biometricLockEnabled ?? false;
  }

  Future<int> getLockTimeoutSeconds(int userId) async {
    final row = await getSettings(userId);
    return row?.lockTimeoutSeconds ?? 0;
  }

  Future<void> setBiometricLockEnabled(int userId, bool enabled) async {
    await _ensureRow(userId);
    await (update(db.appSettingsTable)
          ..where((t) => t.userId.equals(userId)))
        .write(AppSettingsTableCompanion(
      biometricLockEnabled: Value(enabled),
    ));
  }

  Future<void> setLockTimeoutSeconds(int userId, int seconds) async {
    await _ensureRow(userId);
    await (update(db.appSettingsTable)
          ..where((t) => t.userId.equals(userId)))
        .write(AppSettingsTableCompanion(
      lockTimeoutSeconds: Value(seconds),
    ));
  }

  Future<DateTime?> getLastAuthenticatedAt(int userId) async {
    final row = await getSettings(userId);
    return row?.lastAuthenticatedAt;
  }

  Future<void> setLastAuthenticatedAt(int userId, DateTime time) async {
    await _ensureRow(userId);
    await (update(db.appSettingsTable)
          ..where((t) => t.userId.equals(userId)))
        .write(AppSettingsTableCompanion(
      lastAuthenticatedAt: Value(time),
    ));
  }

  Future<String> getThemeMode(int userId) async {
    final row = await getSettings(userId);
    return row?.themeMode ?? 'system';
  }

  Future<void> setThemeMode(int userId, String mode) async {
    await _ensureRow(userId);
    await (update(db.appSettingsTable)
          ..where((t) => t.userId.equals(userId)))
        .write(AppSettingsTableCompanion(
      themeMode: Value(mode),
    ));
  }

  Future<int> getTimelineDistanceThreshold(int userId) async {
    final row = await getSettings(userId);
    return row?.timelineDistanceThreshold ?? 50;
  }

  Future<void> setTimelineDistanceThreshold(int userId, int meters) async {
    await _ensureRow(userId);
    await (update(db.appSettingsTable)
          ..where((t) => t.userId.equals(userId)))
        .write(AppSettingsTableCompanion(
      timelineDistanceThreshold: Value(meters),
    ));
  }

  /// Ensures a row exists for the given user, inserting defaults if needed.
  Future<void> _ensureRow(int userId) async {
    final existing = await getSettings(userId);
    if (existing != null) return;
    await into(db.appSettingsTable).insert(
      AppSettingsTableCompanion.insert(userId: Value(userId)),
    );
  }
}



