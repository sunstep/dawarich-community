

import 'package:dawarich/core/data/drift/database/sqlite_client.steps.dart';
import 'package:dawarich/core/data/drift/migrations/drift_v6.dart';
import 'package:dawarich/core/data/drift/migrations/drift_v7.dart';
import 'package:dawarich/core/data/drift/migrations/drift_v8.dart';
import 'package:dawarich/core/data/drift/migrations/drift_v9.dart';
import 'package:dawarich/core/data/drift/migrations/drift_v10.dart';
import 'package:drift/drift.dart';

extension Migrations on GeneratedDatabase {

  OnUpgrade get schemaUpgrade => stepByStep(
      from5To6: migrateToV6,
      from6To7: migrateToV7,
      from7To8: migrateToV8,
      from8To9: migrateToV9,
      from9To10: migrateToV10,
  );
}