import 'package:dawarich/core/di/providers/session_providers.dart';
import 'package:dawarich/core/di/providers/settings_providers.dart';
import 'package:dawarich/core/di/providers/usecase_providers.dart';
import 'package:dawarich/features/points/presentation/viewmodels/points_viewmodel.dart';
import 'package:dawarich/features/timeline/presentation/models/timeline_page_viewmodel.dart';
import 'package:dawarich/features/tracking/presentation/models/tracker_page_viewmodel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final timelineViewModelProvider = FutureProvider<TimelineViewModel>((ref) async {
  final user = ref.watch(authenticatedUserProvider);
  if (user == null) {
    throw StateError('TimelineViewModel requires authenticated user');
  }

  final vm = TimelineViewModel(
    user.id,
    await ref.watch(loadTimelineUseCaseProvider.future),
    ref.watch(timelinePointsProcessorProvider),
    ref.watch(getDefaultMapCenterUseCaseProvider),
    await ref.watch(watchCurrentBatchUseCaseProvider.future),
    await ref.watch(getTimelineDistanceThresholdUseCaseProvider.future),
  );

  vm.initialize();
  ref.onDispose(vm.dispose);
  return vm;
});

final pointsPageViewModelProvider = FutureProvider<PointsViewModel>((ref) async {
  return PointsViewModel(
    await ref.watch(getPointsUseCaseProvider.future),
    await ref.watch(deletePointUseCaseProvider.future),
    await ref.watch(getTotalPagesUseCaseProvider.future),
  );
});

final trackerPageViewModelProvider = FutureProvider<TrackerPageViewModel>((ref) async {
  final user = ref.watch(authenticatedUserProvider);
  if (user == null) {
    throw StateError('TrackerPageViewModel requires authenticated user');
  }

  final vm = TrackerPageViewModel(
    user.id,
    await ref.watch(getTrackerSettingsUseCaseProvider.future),
    await ref.watch(saveTrackerSettingsUseCaseProvider.future),
    ref.watch(getDeviceModelUseCaseProvider),
    await ref.watch(streamLastPointUseCaseProvider.future),
    await ref.watch(streamBatchPointCountUseCaseProvider.future),
    await ref.watch(createPointFromGpsWorkflowProvider.future),
    await ref.watch(storePointUseCaseProvider.future),
    await ref.watch(startTrackUseCaseProvider.future),
    await ref.watch(endTrackUseCaseProvider.future),
    await ref.watch(getActiveTrackUseCaseProvider.future),
    ref.watch(checkSystemSettingsUseCaseProvider),
    ref.watch(openSystemSettingsUseCaseProvider),
  );

  vm.initialize();
  ref.onDispose(vm.dispose);
  return vm;
});
