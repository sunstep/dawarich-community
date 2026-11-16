
import 'package:dawarich/core/network/dio_client.dart';
import 'package:dawarich/features/stats/data/data_transfer_objects/stats/stats_dto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:option_result/option_result.dart';

abstract interface class IStatsRemoteDataSource {
  Future<Option<StatsDTO>> fetchStats();
}


final class StatsRemoteDataSource implements IStatsRemoteDataSource {
  final DioClient _apiClient;

  StatsRemoteDataSource(this._apiClient);

  @override
  Future<Option<StatsDTO>> fetchStats() async {
    try {
      final resp = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/stats',
        options: Options(receiveTimeout: const Duration(seconds: 30)),
      );

      final json = resp.data;
      if (json == null || json.isEmpty) {
        return const None();
      }

      return Some(StatsDTO.fromJson(json));
    } catch (e) {
      // Catches DioException (network errors) as well as JSON parsing errors
      // so the repository can always fall back to its local cache.
      debugPrint('Failed to retrieve stats: $e');
      return const None();
    }
  }
}