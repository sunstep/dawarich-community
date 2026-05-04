import 'package:dawarich/core/data/drift/database/sqlite_client.dart';
import 'package:dawarich/core/network/configs/api_config_manager.dart';
import 'package:dawarich/core/network/configs/api_config_manager_interfaces.dart';
import 'package:dawarich/core/network/dio_client.dart';
import 'package:dawarich/core/network/interceptors/auth_interceptor.dart';
import 'package:dawarich/core/network/interceptors/error_interceptor.dart';
import 'package:dawarich/core/shell/drawer/i_api_config_logout.dart';
import 'package:dawarich/features/tracking/data/sources/connectivity_data_client.dart';
import 'package:dawarich/features/tracking/data/sources/device_data_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final coreProvider = FutureProvider<void>((ref) async {
  await ref.watch(apiConfigManagerProvider.future);
  await ref.watch(sqliteClientProvider.future);
  await ref.watch(dioClientProvider.future);
});

final apiConfigManagerProvider = FutureProvider<IApiConfigManager>((ref) async {
  if (kDebugMode) {
    debugPrint('[RP - Core] ApiConfigManager.load start');
  }

  final cfg = ApiConfigManager();
  await cfg.load();

  if (kDebugMode) {
    debugPrint('[RP - Core] ApiConfigManager.load finished');
  }

  return cfg;
});

final apiConfigLogoutProvider = FutureProvider<IApiConfigLogout>((ref) async {
  final manager = await ref.watch(apiConfigManagerProvider.future);

  return manager as IApiConfigLogout;
});

final authInterceptorProvider = FutureProvider<AuthInterceptor>((ref) async {
  final cfg = await ref.watch(apiConfigManagerProvider.future);
  return AuthInterceptor(cfg);
});

final errorInterceptorProvider = Provider<ErrorInterceptor>((ref) {
  return ErrorInterceptor();
});

final dioClientProvider = FutureProvider<DioClient>((ref) async {
  final auth = await ref.watch(authInterceptorProvider.future);
  final err = ref.watch(errorInterceptorProvider);
  return DioClient([auth, err]);
});

final sqliteClientProvider = FutureProvider<SQLiteClient>((ref) async {
  if (kDebugMode) {
    debugPrint('[RP - Core] loading SQLiteClient...');
  }

  final client = await SQLiteClient.connectSharedIsolate();

  if (kDebugMode) {
    debugPrint('[RP - Core] SQLiteClient loaded.');
  }

  // Note: We don't dispose the client here because the underlying isolate
  // is shared across the app. Closing it would break other clients.

  return client;
});

final deviceDataClientProvider = Provider<DeviceDataClient>((ref) {
  return DeviceDataClient();
});

final connectivityDataClientProvider = Provider<ConnectivityDataClient>((ref) {
  return ConnectivityDataClient();
});

