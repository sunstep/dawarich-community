import 'package:dawarich/core/di/providers/core_providers.dart';
import 'package:dawarich/features/settings/application/repositories/app_settings_repository_interfaces.dart';
import 'package:dawarich/features/settings/application/usecases/authenticate_biometric_usecase.dart';
import 'package:dawarich/features/settings/application/usecases/check_biometric_availability_usecase.dart';
import 'package:dawarich/features/settings/application/usecases/get_lock_timeout_usecase.dart';
import 'package:dawarich/features/settings/application/usecases/get_theme_mode_usecase.dart';
import 'package:dawarich/features/settings/application/usecases/get_timeline_distance_threshold_usecase.dart';
import 'package:dawarich/features/settings/application/usecases/is_biometric_lock_enabled_usecase.dart';
import 'package:dawarich/features/settings/application/usecases/set_biometric_lock_enabled_usecase.dart';
import 'package:dawarich/features/settings/application/usecases/set_lock_timeout_usecase.dart';
import 'package:dawarich/features/settings/application/usecases/set_theme_mode_usecase.dart';
import 'package:dawarich/features/settings/application/usecases/set_timeline_distance_threshold_usecase.dart';
import 'package:dawarich/features/settings/data/repositories/app_settings_repository.dart';
import 'package:dawarich/features/settings/data/sources/local/app_settings_local_data_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// --- Data sources ---

final appSettingsLocalDataSourceProvider =
    FutureProvider<IAppSettingsLocalDataSource>((ref) async {
  final db = await ref.watch(sqliteClientProvider.future);
  return AppSettingsLocalDataSource(db.appSettingsDao);
});

// --- Repositories ---

final appSettingsRepositoryProvider =
    FutureProvider<IAppSettingsRepository>((ref) async {
  final local = await ref.watch(appSettingsLocalDataSourceProvider.future);
  return AppSettingsRepository(local);
});

// --- Use cases ---

final isBiometricLockEnabledUseCaseProvider =
    FutureProvider<IsBiometricLockEnabledUseCase>((ref) async {
  final repo = await ref.watch(appSettingsRepositoryProvider.future);
  return IsBiometricLockEnabledUseCase(repo);
});

final setBiometricLockEnabledUseCaseProvider =
    FutureProvider<SetBiometricLockEnabledUseCase>((ref) async {
  final repo = await ref.watch(appSettingsRepositoryProvider.future);
  return SetBiometricLockEnabledUseCase(repo);
});

final getLockTimeoutUseCaseProvider =
    FutureProvider<GetLockTimeoutUseCase>((ref) async {
  final repo = await ref.watch(appSettingsRepositoryProvider.future);
  return GetLockTimeoutUseCase(repo);
});

final setLockTimeoutUseCaseProvider =
    FutureProvider<SetLockTimeoutUseCase>((ref) async {
  final repo = await ref.watch(appSettingsRepositoryProvider.future);
  return SetLockTimeoutUseCase(repo);
});

final getThemeModeUseCaseProvider =
    FutureProvider<GetThemeModeUseCase>((ref) async {
  final repo = await ref.watch(appSettingsRepositoryProvider.future);
  return GetThemeModeUseCase(repo);
});

final setThemeModeUseCaseProvider =
    FutureProvider<SetThemeModeUseCase>((ref) async {
  final repo = await ref.watch(appSettingsRepositoryProvider.future);
  return SetThemeModeUseCase(repo);
});

final getTimelineDistanceThresholdUseCaseProvider =
    FutureProvider<GetTimelineDistanceThresholdUseCase>((ref) async {
  final repo = await ref.watch(appSettingsRepositoryProvider.future);
  return GetTimelineDistanceThresholdUseCase(repo);
});

final setTimelineDistanceThresholdUseCaseProvider =
    FutureProvider<SetTimelineDistanceThresholdUseCase>((ref) async {
  final repo = await ref.watch(appSettingsRepositoryProvider.future);
  return SetTimelineDistanceThresholdUseCase(repo);
});

final checkBiometricAvailabilityUseCaseProvider =
    Provider<CheckBiometricAvailabilityUseCase>(
        (_) => CheckBiometricAvailabilityUseCase());

final authenticateBiometricUseCaseProvider =
    Provider<AuthenticateBiometricUseCase>(
        (_) => AuthenticateBiometricUseCase());

// --- Reactive theme mode ---

/// A notifier that holds the current ThemeMode and can be updated
/// from the settings view. The main app widget watches this.
final class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void set(ThemeMode mode) => state = mode;
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// Helper to convert between string and ThemeMode.
ThemeMode themeModeFromString(String mode) {
  switch (mode) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

String themeModeToString(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return 'light';
    case ThemeMode.dark:
      return 'dark';
    case ThemeMode.system:
      return 'system';
  }
}

String themeModeLabel(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return 'Light';
    case ThemeMode.dark:
      return 'Dark';
    case ThemeMode.system:
      return 'System default';
  }
}
