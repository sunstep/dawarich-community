import 'package:dawarich/features/stats/data/data_transfer_objects/stats/stats_dto.dart';
import 'package:dawarich/features/stats/application/repositories/stats_repository_interfaces.dart';
import 'package:dawarich/features/stats/data/sources/local/stats_local_data_source.dart';
import 'package:dawarich/features/stats/data/sources/remote/stats_remote_data_source.dart';
import 'package:option_result/option_result.dart';

final class StatsRepository implements IStatsRepository {
  final IStatsRemoteDataSource _remote;
  final IStatsCacheDataSource _cache;

  StatsRepository({
    required IStatsRemoteDataSource remote,
    required IStatsCacheDataSource cache,
  })  : _remote = remote,
        _cache = cache;

  @override
  Future<Option<StatsDTO>> getStats(int userId, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await _cache.getCachedStats(userId);
      if (cached.isSome()) {
        return Some(cached.unwrap().stats);
      }
    }

    final remote = await _remote.fetchStats();
    if (remote.isSome()) {
      await _cache.upsert(userId,
        stats: remote.unwrap(),
        syncedAt: DateTime.now(),
      );
      return remote;
    }

    // Remote call failed (e.g. offline). Fall back to the cached version so a
    // forceRefresh while offline doesn't wipe the displayed stats.
    final cached = await _cache.getCachedStats(userId);
    if (cached.isSome()) {
      return Some(cached.unwrap().stats);
    }

    return remote; // None — no cache and no network
  }

  @override
  Future<Option<DateTime>> getLastSyncedAt(int userId) {
    return _cache.getLastSyncedAt(userId);
  }
}