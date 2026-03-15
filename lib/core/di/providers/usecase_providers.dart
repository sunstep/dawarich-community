import 'package:dawarich/core/application/usecases/api/delete_point_usecase.dart';
import 'package:dawarich/core/application/usecases/api/get_points_usecase.dart';
import 'package:dawarich/core/application/usecases/api/get_total_pages_usecase.dart';
import 'package:dawarich/features/batch/application/usecases/batch_upload_workflow_usecase.dart';
import 'package:dawarich/features/batch/application/usecases/check_and_upload_expired_batch_usecase.dart';
import 'package:dawarich/features/batch/application/usecases/check_batch_threshold_usecase.dart';
import 'package:dawarich/features/batch/application/usecases/get_current_batch_usecase.dart';
import 'package:dawarich/features/stats/application/repositories/countries_repository_interfaces.dart';
import 'package:dawarich/features/stats/application/repositories/stats_repository_interfaces.dart';
import 'package:dawarich/features/stats/application/usecases/get_last_stats_sync_usecase.dart';
import 'package:dawarich/features/stats/application/usecases/get_stats_usecase.dart';
import 'package:dawarich/features/stats/application/usecases/get_visited_countries_usecase.dart';
import 'package:dawarich/features/stats/application/usecases/should_refresh_stats_usecase.dart';
import 'package:dawarich/features/stats/data/mappers/countries_mapper.dart';
import 'package:dawarich/features/stats/data/repositories/countries_repository.dart';
import 'package:dawarich/features/stats/data/repositories/stats_repository.dart';
import 'package:dawarich/features/stats/data/sources/local/stats_local_data_source.dart';
import 'package:dawarich/features/stats/data/sources/remote/stats_remote_data_source.dart';
import 'package:dawarich/features/stats/presentation/converters/countries_mapper.dart';
import 'package:dawarich/features/tracking/application/repositories/location_provider_interface.dart';
import 'package:dawarich/features/tracking/application/services/tracking_notification_service.dart';
import 'package:dawarich/features/tracking/application/usecases/notifications/cancel_tracker_notification_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/notifications/initialize_tracker_notification_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/notifications/was_launched_from_notification_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/point_creation/create_point_usecase.dart';
import 'package:dawarich/features/tracking/data/repositories/location_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core_providers.dart';
import 'package:dawarich/core/data/repositories/drift/drift_local_point_repository.dart';
import 'package:dawarich/core/data/repositories/drift/drift_track_repository.dart';
import 'package:dawarich/core/data/repositories/local_point_repository_interfaces.dart';
import 'package:dawarich/core/network/repositories/api_point_repository.dart';
import 'package:dawarich/core/network/repositories/api_point_repository_interfaces.dart';
import 'package:dawarich/features/batch/application/usecases/watch_current_batch_usecase.dart';
import 'package:dawarich/features/timeline/application/helpers/timeline_points_processor.dart';
import 'package:dawarich/features/timeline/application/usecases/load_timeline_usecase.dart';
import 'package:dawarich/features/tracking/application/repositories/hardware_repository_interfaces.dart';
import 'package:dawarich/features/tracking/application/repositories/i_track_repository.dart';
import 'package:dawarich/features/tracking/application/repositories/tracker_settings_repository.dart';
import 'package:dawarich/features/tracking/application/services/point_automation_service.dart';
import 'package:dawarich/features/tracking/application/usecases/get_batch_point_count_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/get_last_point_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/notifications/show_tracker_notification_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/point_creation/create_point_from_cache_workflow.dart';
import 'package:dawarich/features/tracking/application/usecases/point_creation/create_point_from_gps_workflow.dart';
import 'package:dawarich/features/tracking/application/usecases/point_creation/create_point_from_location_stream_workflow.dart';
import 'package:dawarich/features/tracking/application/usecases/point_creation/store_point_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/settings/get_device_model_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/settings/get_tracker_settings_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/settings/save_tracker_settings_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/settings/watch_tracker_settings_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/stream_last_point_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/track/get_active_track_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/track/start_track_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/track/end_track_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/track/watch_batch_point_count_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/system_settings/check_system_settings_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/system_settings/open_system_settings_usecase.dart';
import 'package:dawarich/features/tracking/data/repositories/hardware_repository.dart';
import 'package:dawarich/features/tracking/data/repositories/drift_tracker_settings_repository.dart';
import 'package:dawarich/features/batch/application/usecases/point_validator.dart';
import 'package:dawarich/features/timeline/application/usecases/get_default_map_center_usecase.dart';

final statsRemoteDataSourceProvider = FutureProvider<IStatsRemoteDataSource>((ref) async {
  final dio = await ref.watch(dioClientProvider.future);
  return StatsRemoteDataSource(dio);
});

final statsCacheDataSourceProvider = FutureProvider<IStatsCacheDataSource>((ref) async {
  final db = await ref.watch(sqliteClientProvider.future);

  return StatsCacheDataSource(db.statsCacheDao);

});

// --- Repositories ---
final apiPointRepositoryProvider = FutureProvider<IApiPointRepository>((ref) async {
  final dio = await ref.watch(dioClientProvider.future);
  return ApiPointRepository(dio);
});

final pointLocalRepositoryProvider = FutureProvider<IPointLocalRepository>((ref) async {
  final db = await ref.watch(sqliteClientProvider.future);
  return DriftPointLocalRepository(db);
});

final statsRepositoryProvider = FutureProvider<IStatsRepository>((ref) async {
  final remote = await ref.watch(statsRemoteDataSourceProvider.future);
  final cache = await ref.watch(statsCacheDataSourceProvider.future);

  return StatsRepository(remote: remote, cache: cache);
});
// --- Tracking repositories ---
final hardwareRepositoryProvider = Provider<IHardwareRepository>((ref) {
  return HardwareRepository(
    ref.watch(deviceDataClientProvider),
    ref.watch(connectivityDataClientProvider),
  );
});

final locationProviderProvider = Provider<ILocationProvider>((ref) {
  return LocationProvider();
});

final trackerSettingsRepositoryProvider = FutureProvider<ITrackerSettingsRepository>((ref) async {
  final db = await ref.watch(sqliteClientProvider.future);
  final hw = ref.watch(hardwareRepositoryProvider);
  return DriftTrackerSettingsRepository(db, hw);
});

final trackRepositoryProvider = FutureProvider<ITrackRepository>((ref) async {
  final db = await ref.watch(sqliteClientProvider.future);
  return DriftTrackRepository(db);
});

// --- Use cases ---
final getPointsUseCaseProvider = FutureProvider<GetPointsUseCase>((ref) async {
  return GetPointsUseCase(await ref.watch(apiPointRepositoryProvider.future));
});

final deletePointUseCaseProvider = FutureProvider<DeletePointUseCase>((ref) async {
  return DeletePointUseCase(await ref.watch(apiPointRepositoryProvider.future));
});

final getTotalPagesUseCaseProvider = FutureProvider<GetTotalPagesUseCase>((ref) async {
  return GetTotalPagesUseCase(await ref.watch(apiPointRepositoryProvider.future));
});

final getStatsUseCaseProvider = FutureProvider<GetStatsUseCase>((ref) async {
  return GetStatsUseCase(await ref.watch(statsRepositoryProvider.future));
});

final getLastStatsSyncUseCaseProvider = FutureProvider<GetLastStatsSyncUsecase>((ref) async {
  return GetLastStatsSyncUsecase(await ref.watch(statsRepositoryProvider.future));
});

final shouldRefreshStatsUseCaseProvider =
FutureProvider<ShouldRefreshStatsUseCase>((ref) async {
  final getLastSync = await ref.watch(getLastStatsSyncUseCaseProvider.future);
  return ShouldRefreshStatsUseCase(getLastSync);
});


// --- Countries repositories ---

final countriesDtoMapperProvider = Provider<VisitedCountriesDataMapper>((ref) {
  return VisitedCountriesDataMapper();
});

final countriesUiMapperProvider = Provider<VisitedCountriesUiMapper>((ref) {
  return VisitedCountriesUiMapper();
});

final countriesRepositoryProvider = FutureProvider<ICountriesRepository>((ref) async {
  final dio = await ref.watch(dioClientProvider.future);
  final mapper = ref.watch(countriesDtoMapperProvider);
  return CountriesRepository(dio, mapper);
});

// --- Countries use case ---
final getVisitedCountriesUseCaseProvider = FutureProvider<GetVisitedCountriesUseCase>((ref) async {
  final repo = await ref.watch(countriesRepositoryProvider.future);
  return GetVisitedCountriesUseCase(repo);
});

// --- Tracking usecases ---
final storePointUseCaseProvider = FutureProvider<StorePointUseCase>((ref) async {
  final repo = await ref.watch(pointLocalRepositoryProvider.future);
  return StorePointUseCase(repo);
});

final getTrackerSettingsUseCaseProvider = FutureProvider<GetTrackerSettingsUseCase>((ref) async {
  final repo = await ref.watch(trackerSettingsRepositoryProvider.future);
  return GetTrackerSettingsUseCase(repo);
});

final watchTrackerSettingsUseCaseProvider = FutureProvider<WatchTrackerSettingsUseCase>((ref) async {
  final repo = await ref.watch(trackerSettingsRepositoryProvider.future);
  return WatchTrackerSettingsUseCase(repo);
});

final trackerNotificationServiceProvider = Provider<TrackerNotificationService>((ref) {
  return TrackerNotificationService();
});

final initializeTrackerNotificationServiceUseCaseProvider =
Provider<InitializeTrackerNotificationServiceUseCase>((ref) {
  return InitializeTrackerNotificationServiceUseCase(
    ref.watch(trackerNotificationServiceProvider),
  );
});


final showTrackerNotificationUseCaseProvider = Provider<ShowTrackerNotificationUseCase>((ref) {
  return ShowTrackerNotificationUseCase(
    ref.watch(trackerNotificationServiceProvider),
  );
});

final cancelTrackerNotificationUseCaseProvider = Provider<CancelTrackerNotificationUseCase>((ref) {
  return CancelTrackerNotificationUseCase(
    ref.watch(trackerNotificationServiceProvider),
  );
});

final wasLaunchedFromNotificationUseCaseProvider = Provider<WasLaunchedFromNotificationUseCase>((ref) {
  return WasLaunchedFromNotificationUseCase(
    ref.watch(trackerNotificationServiceProvider),
  );
});
final getBatchPointCountUseCaseProvider = FutureProvider<GetBatchPointCountUseCase>((ref) async {
  final repo = await ref.watch(pointLocalRepositoryProvider.future);
  return GetBatchPointCountUseCase(repo);
});

final checkAndUploadExpiredBatchUseCaseProvider = FutureProvider<CheckAndUploadExpiredBatchUseCase>((ref) async {
  final getSettings = await ref.watch(getTrackerSettingsUseCaseProvider.future);
  final localRepo = await ref.watch(pointLocalRepositoryProvider.future);
  final getCurrentBatch = await ref.watch(getCurrentBatchUseCaseProvider.future);
  final batchUploadWorkflow = await ref.watch(batchUploadWorkflowUseCaseProvider.future);

  return CheckAndUploadExpiredBatchUseCase(getSettings, localRepo, getCurrentBatch, batchUploadWorkflow);
});

final getLastPointUseCaseProvider = FutureProvider<GetLastPointUseCase>((ref) async {
  final repo = await ref.watch(pointLocalRepositoryProvider.future);
  return GetLastPointUseCase(repo);
});

final pointValidatorProvider = FutureProvider<PointValidator>((ref) async {
  final getSettings = await ref.watch(getTrackerSettingsUseCaseProvider.future);
  return PointValidator(getSettings);
});

final createPointFromPositionUseCaseProvider = FutureProvider<CreatePointUseCase>((ref) async {
  final validator = await ref.watch(pointValidatorProvider.future);
  final apiRepo = await ref.watch(apiPointRepositoryProvider.future);
  return CreatePointUseCase(
    ref.watch(hardwareRepositoryProvider),
    await ref.watch(pointLocalRepositoryProvider.future),
    await ref.watch(trackRepositoryProvider.future),
    validator,
    apiRepo,
  );
});

final createPointFromGpsWorkflowProvider = FutureProvider<CreatePointFromGpsWorkflow>((ref) async {
  final prefs = await ref.watch(getTrackerSettingsUseCaseProvider.future);
  final createFromPos = await ref.watch(createPointFromPositionUseCaseProvider.future);
  final locationProvider = ref.watch(locationProviderProvider);
  return CreatePointFromGpsWorkflow(prefs, locationProvider, createFromPos);
});

final createPointFromCacheWorkflowProvider = FutureProvider<CreatePointFromCacheWorkflow>((ref) async {
  final createFromPos = await ref.watch(createPointFromPositionUseCaseProvider.future);
  final locationProvider = ref.watch(locationProviderProvider);
  return CreatePointFromCacheWorkflow(locationProvider, createFromPos);
});

final createPointFromLocationStreamWorkflowProvider = FutureProvider<CreatePointFromLocationStreamWorkflow>((ref) async {
  final getSettings = await ref.watch(getTrackerSettingsUseCaseProvider.future);
  final locationProvider = ref.watch(locationProviderProvider);
  final createFromPos = await ref.watch(createPointFromPositionUseCaseProvider.future);
  return CreatePointFromLocationStreamWorkflow(getSettings, locationProvider, createFromPos);
});

final pointAutomationServiceProvider = FutureProvider<PointAutomationService>((ref) async {
  final createStream = await ref.watch(createPointFromLocationStreamWorkflowProvider.future);
  final storePoint = await ref.watch(storePointUseCaseProvider.future);
  final batchCount = await ref.watch(getBatchPointCountUseCaseProvider.future);
  final showNotif = ref.watch(showTrackerNotificationUseCaseProvider);
  final watchSettings = await ref.watch(watchTrackerSettingsUseCaseProvider.future);

  final getCurrentBatch = await ref.watch(getCurrentBatchUseCaseProvider.future);
  final batchUploadWorkflow = await ref.watch(batchUploadWorkflowUseCaseProvider.future);
  final localRepo = await ref.watch(pointLocalRepositoryProvider.future);

  return PointAutomationService(
    createStream,
    storePoint,
    batchCount,
    showNotif,
    getCurrentBatch,
    batchUploadWorkflow,
    watchSettings,
    localRepo,
  );
});

final checkBatchThresholdUseCaseProvider = FutureProvider<CheckBatchThresholdUseCase>((ref) async {
  final getSettings = await ref.watch(getTrackerSettingsUseCaseProvider.future);
  final localRepo = await ref.watch(pointLocalRepositoryProvider.future);
  return CheckBatchThresholdUseCase(getSettings, localRepo);
});

final getCurrentBatchUseCaseProvider = FutureProvider<GetCurrentBatchUseCase>((ref) async {
  final localRepo = await ref.watch(pointLocalRepositoryProvider.future);
  return GetCurrentBatchUseCase(localRepo);
});

final batchUploadWorkflowUseCaseProvider = FutureProvider<BatchUploadWorkflowUseCase>((ref) async {
  final apiRepo = await ref.watch(apiPointRepositoryProvider.future);
  final localRepo = await ref.watch(pointLocalRepositoryProvider.future);
  return BatchUploadWorkflowUseCase(apiRepo, localRepo);
});

// --- Timeline helpers / use cases ---
final timelinePointsProcessorProvider = Provider<TimelinePointsProcessor>((ref) {
  return TimelinePointsProcessor();
});

final getDefaultMapCenterUseCaseProvider = Provider<GetDefaultMapCenterUseCase>((ref) {
  return GetDefaultMapCenterUseCase();
});

final loadTimelineUseCaseProvider = FutureProvider<LoadTimelineUseCase>((ref) async {
  return LoadTimelineUseCase(
    await ref.watch(apiPointRepositoryProvider.future),
    ref.watch(timelinePointsProcessorProvider),
  );
});

final watchCurrentBatchUseCaseProvider = FutureProvider<WatchCurrentBatchUseCase>((ref) async {
  final localRepo = await ref.watch(pointLocalRepositoryProvider.future);
  return WatchCurrentBatchUseCase(localRepo);
});

final getDeviceModelUseCaseProvider = Provider<GetDeviceModelUseCase>((ref) {
  return GetDeviceModelUseCase(ref.watch(hardwareRepositoryProvider));
});

final saveTrackerSettingsUseCaseProvider = FutureProvider<SaveTrackerSettingsUseCase>((ref) async {
  return SaveTrackerSettingsUseCase(await ref.watch(trackerSettingsRepositoryProvider.future));
});

final streamLastPointUseCaseProvider = FutureProvider<StreamLastPointUseCase>((ref) async {
  final repo = await ref.watch(pointLocalRepositoryProvider.future);
  return StreamLastPointUseCase(repo);
});

final streamBatchPointCountUseCaseProvider = FutureProvider<StreamBatchPointCountUseCase>((ref) async {
  final repo = await ref.watch(pointLocalRepositoryProvider.future);
  return StreamBatchPointCountUseCase(repo);
});

final startTrackUseCaseProvider = FutureProvider<StartTrackUseCase>((ref) async {
  final repo = await ref.watch(trackRepositoryProvider.future);
  return StartTrackUseCase(repo);
});

final endTrackUseCaseProvider = FutureProvider<EndTrackUseCase>((ref) async {
  final repo = await ref.watch(trackRepositoryProvider.future);
  return EndTrackUseCase(repo);
});

final getActiveTrackUseCaseProvider = FutureProvider<GetActiveTrackUseCase>((ref) async {
  final repo = await ref.watch(trackRepositoryProvider.future);
  return GetActiveTrackUseCase(repo);
});

final checkSystemSettingsUseCaseProvider = Provider<CheckSystemSettingsUseCase>((ref) {
  return CheckSystemSettingsUseCase();
});

final openSystemSettingsUseCaseProvider = Provider<OpenSystemSettingsUseCase>((ref) {
  return OpenSystemSettingsUseCase();
});
