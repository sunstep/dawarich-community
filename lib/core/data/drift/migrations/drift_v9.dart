import 'package:dawarich/core/data/drift/database/sqlite_client.steps.dart';
import 'package:drift/drift.dart';

Future<void> migrateToV9(Migrator m, Schema9 schema) async {
  final result = await m.database.customSelect(
    'PRAGMA table_info(tracker_settings_table)',
  ).get();

  final bool hasBatchExpirationMinutes = result.any(
        (row) => row.data['name'] == 'batch_expiration_minutes',
  );

  if (!hasBatchExpirationMinutes) {
    await m.addColumn(
      schema.trackerSettingsTable,
      schema.trackerSettingsTable.batchExpirationMinutes,
    );
  }
}