import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:dawarich/core/data/drift/database/crypto/db_key_provider.dart';
import 'package:dawarich/core/data/drift/database/crypto/sqlcipher_bootstrap.dart';
import 'package:dawarich/core/data/drift/entities/point/point_geometry_table.dart';
import 'package:dawarich/core/data/drift/entities/point/point_properties_table.dart';
import 'package:dawarich/core/data/drift/entities/point/points_table.dart';
import 'package:dawarich/core/data/drift/entities/settings/app_settings_table.dart';
import 'package:dawarich/core/data/drift/entities/settings/tracker_settings_table.dart';
import 'package:dawarich/core/data/drift/entities/stats/stats_cache_table.dart';
import 'package:dawarich/core/data/drift/entities/track/track_table.dart';
import 'package:dawarich/core/data/drift/entities/user/user_settings_table.dart';
import 'package:dawarich/core/data/drift/entities/user/user_table.dart';
import 'package:dawarich/core/data/drift/database/migrations.dart';
import 'package:dawarich/core/data/drift/daos/app_settings_dao.dart';
import 'package:dawarich/core/data/drift/daos/stats_cache_dao.dart';
import 'package:drift/drift.dart';
import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as s;


part 'sqlite_client.g.dart';

@DriftDatabase(tables: [
  AppSettingsTable,
  PointsTable,
  PointGeometryTable,
  PointPropertiesTable,
  StatsCacheTable,
  TrackTable,
  TrackerSettingsTable,
  UserTable,
  UserSettingsTable,
],
daos: [
  AppSettingsDao,
  StatsCacheDao,
])
final class SQLiteClient extends _$SQLiteClient {

  SQLiteClient(super.executor);

  static String get _dbFileName {

    if (kReleaseMode) {
      return 'dawarich_db.sqlite';
    }

    return 'dawarich_db_dev.sqlite';
  }

  static const _driftPortName = 'dawarich_drift_connect_port';

  static SQLiteClient? _instance;
  static Completer<SQLiteClient>? _pendingInit;

  SQLiteClient._(super.executor);

  /// Factory constructor for testing purposes only
  @visibleForTesting
  factory SQLiteClient.forTesting(DatabaseConnection connection) {
    return SQLiteClient._(connection);
  }

  static Future<SQLiteClient> connectSharedIsolate() async {
    // Fast path: already have a cached instance
    if (_instance != null) {
      if (kDebugMode) {
        debugPrint('[Drift] Reusing cached SQLiteClient instance');
      }
      return _instance!;
    }

    // Wait for any pending initialization
    if (_pendingInit != null) {
      if (kDebugMode) {
        debugPrint('[Drift] Waiting for pending initialization');
      }
      return _pendingInit!.future;
    }

    // Start initialization
    final completer = Completer<SQLiteClient>();
    _pendingInit = completer;

    try {
      if (kDebugMode) {
        debugPrint('[Drift] Initializing database isolate');
      }

      await SqlcipherBootstrap.ensure();

      // Check for existing isolate in IsolateNameServer
      final existing = IsolateNameServer.lookupPortByName(_driftPortName);
      if (existing != null) {
        if (kDebugMode) {
          debugPrint('[Drift] Found existing isolate, connecting to it.');
        }
        try {
          final iso = DriftIsolate.fromConnectPort(existing);
          final conn = await iso.connect().timeout(const Duration(seconds: 1));
          _instance = SQLiteClient._(conn);
          completer.complete(_instance!);
          return _instance!;
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[Drift] Failed to connect to existing isolate: $e');
          }
          IsolateNameServer.removePortNameMapping(_driftPortName);
        }
      }

      if (kDebugMode) {
        debugPrint('[Drift] Creating new database isolate');
      }

      final dir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(dir.path, _dbFileName);

      final ready = ReceivePort();
      final String hexKey = await DbKeyProvider().getOrCreateHexKey();
      final RootIsolateToken? token = RootIsolateToken.instance;

      await Isolate.spawn(_dbIsolateEntry, [ready.sendPort, dbPath, hexKey, token]);

      final iso = await ready.first.timeout(const Duration(seconds: 10)) as DriftIsolate;

      final registered = IsolateNameServer.registerPortWithName(iso.connectPort, _driftPortName);
      if (!registered) {
        // Another isolate was registered while we were creating ours
        if (kDebugMode) {
          debugPrint('[Drift] Another isolate was registered, using that one');
        }
        final port = IsolateNameServer.lookupPortByName(_driftPortName)!;
        final existingIso = DriftIsolate.fromConnectPort(port);
        final conn = await existingIso.connect();
        _instance = SQLiteClient._(conn);
        completer.complete(_instance!);
        _pendingInit = null;
        return _instance!;
      }

      if (kDebugMode) {
        debugPrint('[Drift] Database isolate created and registered');
      }

      final conn = await iso.connect().timeout(const Duration(seconds: 10));
      _instance = SQLiteClient._(conn);
      completer.complete(_instance!);
      _pendingInit = null;
      return _instance!;
    } catch (e, s) {
      _pendingInit = null;
      completer.completeError(e, s);
      rethrow;
    }
  }

  static bool _hasSqlCipher(s.Database database) {
    return database.select('PRAGMA cipher_version;').isNotEmpty;
  }

  static void _dbIsolateEntry(List<dynamic> args) {
    () async {
      final send = args[0] as SendPort;
      final dbPath = args[1] as String;
      final hexKey = args[2] as String;
      final RootIsolateToken? token = args[3] as RootIsolateToken?;

      if (Platform.isAndroid && token != null) {
        BackgroundIsolateBinaryMessenger.ensureInitialized(token);
      }

      await SqlcipherBootstrap.ensure();

      final driftIso = DriftIsolate.inCurrent(() {
        final executor = NativeDatabase(
            File(dbPath),
            logStatements: kDebugMode,
            setup: (rawDb) {
              // Set busy_timeout FIRST so every subsequent write operation
              // (cipher setup, WAL activation, migrations, data writes) waits
              // up to 5 s for the lock instead of failing with SQLITE_BUSY
              // immediately.  This is critical because flutter_background_service
              // creates a SEPARATE FlutterEngine / Dart VM, so IsolateNameServer
              // is NOT shared between the main app and the background service —
              // both VMs open independent Drift connections to the same file and
              // can contend on writes at startup.
              rawDb.execute('PRAGMA busy_timeout = 5000;');

              assert(_hasSqlCipher(
                  rawDb), 'SQLCipher not available: check deps & bootstrap');
              rawDb.execute('PRAGMA cipher_compatibility = 4;');
              rawDb.execute('PRAGMA key = "x\'$hexKey\'";');
              rawDb.select('PRAGMA cipher_version;');
              rawDb.config.doubleQuotedStringLiterals = false;
              rawDb.execute('PRAGMA foreign_keys = ON;');
              rawDb.execute('PRAGMA journal_mode = WAL;');
            }
        );
        return DatabaseConnection(executor);
      });

      send.send(driftIso);
    }
    ();
  }


  // Database path helper
  static Future<String> dbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, _dbFileName);
  }


  static const int kSchemaVersion = 10;
  @override
  int get schemaVersion => kSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (final m) async {

      if (kDebugMode) {
        debugPrint("[Drift] Creating new database...");
      }

      await m.createAll();
    },
    onUpgrade: schemaUpgrade,
    beforeOpen: (details) async {

      if (kDebugMode) {
        debugPrint('[Drift] Database opening at schema version: ${details.versionNow}');
      }

      await customStatement('PRAGMA journal_mode = WAL;');

      // Do whatever you like here if needed, this will always run before the db opens.
    },
  );

}
