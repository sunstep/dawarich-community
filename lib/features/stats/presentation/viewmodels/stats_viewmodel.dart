import 'dart:async';

import 'package:dawarich/core/di/providers/session_providers.dart';
import 'package:dawarich/core/di/providers/usecase_providers.dart';
import 'package:dawarich/core/domain/models/user.dart';
import 'package:dawarich/features/stats/application/usecases/get_stats_usecase.dart';
import 'package:dawarich/features/stats/domain/stats/stats.dart';
import 'package:dawarich/features/stats/presentation/converters/stats_page_model_converter.dart';
import 'package:dawarich/features/stats/presentation/models/stats/stats_uimodel.dart';
import 'package:dawarich/features/stats/presentation/viewmodels/stats_page_state.dart';
import 'package:option_result/option.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'stats_viewmodel.g.dart';

/// AsyncNotifier that manages stats page state
@Riverpod()
class StatsViewmodel extends _$StatsViewmodel {

  @override
  FutureOr<StatsPageState?> build() async {

    final getStats = await ref.watch(getStatsUseCaseProvider.future);
    final getLastSyncedAt = await ref.watch(getLastStatsSyncUseCaseProvider.future);
    final User user = ref.watch(currentUserProvider);
    final int userId = user.id;

    final (statsOpt, lastSyncedAtUtc) = await (
      getStats(userId),
      getLastSyncedAt(userId),
    ).wait;

    if (statsOpt case Some(value: final stats)) {
      return StatsPageState(
        stats: stats.toUiModel(),
        syncedAtUtc: lastSyncedAtUtc,
      );
    }

    return StatsPageState(
      stats: null,
      syncedAtUtc: lastSyncedAtUtc,
    );
  }

  Future<void> refresh() async {
    // Remember the last successfully loaded state so we can restore it if the
    // refresh fails (e.g. offline) rather than blanking the screen.
    final StatsPageState? previousData = state.value;

    state = const AsyncLoading();

    try {
      final getStats = await ref.read(getStatsUseCaseProvider.future);
      final getLastSyncedAt =
          await ref.read(getLastStatsSyncUseCaseProvider.future);

      final User user = ref.read(currentUserProvider);
      final int userId = user.id;

      final StatsUiModel? stats = await _fetchStats(
        userId,
        getStats,
        forceRefresh: true,
      );

      final DateTime? lastSyncedAtUtc = await getLastSyncedAt(userId);

      state = AsyncData(StatsPageState(
        stats: stats,
        syncedAtUtc: lastSyncedAtUtc,
      ));
    } catch (e, st) {
      // On any failure, restore the last known good state so cached stats
      // remain visible rather than disappearing.
      if (previousData != null) {
        state = AsyncData(previousData);
      } else {
        state = AsyncError(e, st);
      }
    }
  }

  Future<StatsUiModel?> _fetchStats(
      int userId,
      GetStatsUseCase useCase, {
        bool forceRefresh = false,
      }) async {
    final Option<Stats> result = await useCase(userId, forceRefresh: forceRefresh);

    if (result case Some(value: final Stats stats)) {
      return stats.toUiModel();
    }

    return null;
  }

}