import 'package:drift/drift.dart';

/// Stores app-wide preferences (one row per user).
class AppSettingsTable extends Table {
  IntColumn get userId => integer()();

  BoolColumn get biometricLockEnabled =>
      boolean().withDefault(const Constant(false))();

  /// Seconds of inactivity before the app locks. 0 = immediately.
  IntColumn get lockTimeoutSeconds =>
      integer().withDefault(const Constant(0))();

  /// When the user last successfully authenticated via biometric/screen lock.
  DateTimeColumn get lastAuthenticatedAt => dateTime().nullable()();

  /// Theme mode: 'system', 'light', or 'dark'.
  TextColumn get themeMode =>
      text().withDefault(const Constant('system'))();

  /// Minimum distance (in metres) between consecutive points shown on the
  /// timeline.  Points closer than this threshold are merged.  Default: 50 m.
  IntColumn get timelineDistanceThreshold =>
      integer().withDefault(const Constant(50))();

  @override
  Set<Column> get primaryKey => {userId};
}


