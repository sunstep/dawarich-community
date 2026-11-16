import 'package:dawarich/core/data/drift/database/sqlite_client.steps.dart';
import 'package:drift/drift.dart';

/// Adds [timeline_distance_threshold] to [app_settings_table].
///
/// Default 50 m — matches the previous hard-coded value in
/// [TimelinePointsProcessor._mergePoints] so existing installs behave
/// identically after the upgrade.
Future<void> migrateToV10(Migrator m, Schema10 schema) async {
  final result = await m.database.customSelect(
    'PRAGMA table_info(app_settings_table)',
  ).get();

  final bool hasColumn = result.any(
    (row) => row.data['name'] == 'timeline_distance_threshold',
  );

  if (!hasColumn) {
    await m.addColumn(
      schema.appSettingsTable,
      schema.appSettingsTable.timelineDistanceThreshold,
    );
  }
}

