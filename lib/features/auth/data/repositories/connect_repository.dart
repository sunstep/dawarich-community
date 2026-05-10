import 'package:dawarich/features/auth/data/data_transfer_objects/users/user_dto.dart';
import 'package:dawarich/features/auth/application/repositories/connect_repository_interfaces.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';
import 'package:option_result/option_result.dart';

final class ConnectRepository implements IConnectRepository {

  static const _timeout = Duration(seconds: 20);

  String _normalizeBase(String hostWithProtocol) {
    return hostWithProtocol.trim().replaceAll(RegExp(r'\/+$'), '');
  }

  Dio _createPlainDio(String baseUrl, {String? apiKey}) {
    final options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: _timeout,
      receiveTimeout: _timeout,
      responseType: ResponseType.json,
      headers: apiKey == null
          ? null
          : <String, dynamic>{
        'Authorization': 'Bearer $apiKey',
      },
    );

    final dioClient = Dio(options);
    dioClient.httpClientAdapter = NativeAdapter();
    return dioClient;
  }

  @override
  Future<bool> testHost(String hostWithProtocol) async {
    final base = _normalizeBase(hostWithProtocol);
    final dio = _createPlainDio(base);

    try {
      final resp = await dio.get('/api/v1/health');
      return resp.statusCode == 200;
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('[testHost] failed for $base: ${e.type} ${e.message}');
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[testHost] failed for $base: $e');
      }
      return false;
    }
  }

  @override
  Future<Result<UserDto, String>> loginApiKeyOnHost({
    required String hostWithProtocol,
    required String apiKey,
  }) async {
    final base = _normalizeBase(hostWithProtocol);
    final cleanedKey = apiKey.trim();

    final dio = _createPlainDio(base, apiKey: cleanedKey);

    try {
      final resp = await dio.get<Map<String, dynamic>>('/api/v1/users/me');

      final data = resp.data;
      if (data == null || data['user'] is! Map<String, dynamic>) {
        return Err('Invalid response from server.');
      }

      final userJson = data['user'] as Map<String, dynamic>;

      final user = UserDto.fromRemote(userJson)
          .withDawarichEndpoint(base);

      return Ok(user);
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('[loginApiKeyOnHost] failed for $base: ${e.response?.statusCode} ${e.message}');
      }

      final msg = e.message ?? 'Failed to verify API key';

      return Err(msg);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[loginApiKeyOnHost] error: $e');
      }
      return Err('Error while fetching user data: $e');
    }
  }
}
