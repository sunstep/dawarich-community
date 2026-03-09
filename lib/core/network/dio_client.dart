import 'package:dawarich/core/network/errors/remote_request_failure.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';
import 'package:option_result/option_result.dart';

final class DioClient {

  final Dio _dio;

  DioClient(List<Interceptor> interceptors)
      : _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 20),
  )) {
    _dio.interceptors.addAll(interceptors);
    _dio.httpClientAdapter = NativeAdapter();

    assert(() {
      _dio.interceptors.add(LogInterceptor(
        request: kDebugMode,
        requestBody: kDebugMode,
        responseBody: kDebugMode,
        error: kDebugMode,
      ));
      return true;
    }());
  }

  Future<Result<T, RemoteRequestFailure>> safe<T>(Future<T> Function() block) async {
    try {
      final v = await block();
      return Ok(v);
    } on DioException catch (e) {
      final f = e.error is RemoteRequestFailure
          ? e.error as RemoteRequestFailure
          : UnexpectedFailure(technical: e.message, statusCode: e.response?.statusCode);
      return Err(f);
    } catch (e) {
      return Err(UnexpectedFailure(technical: e.toString()));
    }
  }

  Future<Result<R, RemoteRequestFailure>> getJson<R>(
      String path, {
        required R Function(dynamic json) map,
        Map<String, dynamic>? query,
        Options? options,
        CancelToken? cancel,
      }) {
    return safe(() async {
      final res = await get<dynamic>(path,
          queryParameters: query, options: options, cancelToken: cancel);
      return map(res.data);
    });
  }

  Future<Result<R, RemoteRequestFailure>> postJson<R>(
      String path, {
        required Object data,
        required R Function(dynamic json) map,
        Map<String, dynamic>? query,
        Options? options,
        CancelToken? cancel,
      }) {
    return safe(() async {
      final res = await post<dynamic>(path,
          data: data,
          queryParameters: query,
          options: options ?? Options(contentType: 'application/json'),
          cancelToken: cancel);
      return map(res.data);
    });
  }

  Future<Response<T>> get<T>(String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    Function(int, int)? onReceiveProgress}) {
    return _dio.get(path,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress);
  }

  Future<Response<T>> post<T>(String path, {
    required Object data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    Function(int, int)? onSendProgress,
    Function(int, int)? onReceiveProgress}) {
    return _dio.post(path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress
    );
  }

  Future<Response<T>> delete<T>(String path, {
      Object? data,
      Map<String, dynamic>? queryParameters,
      Options? options,
      CancelToken? cancelToken }) {
    return _dio.delete(path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken);
  }

  Future<Response<T>> head<T>(String path,
      {Object? data,
      Map<String, dynamic>? queryParameters,
      Options? options,
      CancelToken? cancelToken}) {
    return _dio.head(path,
        data: data, queryParameters: queryParameters, options: options);
  }

  Future<Response<T>> put<T>(String path,
      {Object? data,
        Map<String, dynamic>? queryParameters,
        Options? options,
        CancelToken? cancelToken}) {
    return _dio.put(path,
        data: data, queryParameters: queryParameters, options: options);
  }

  Future<Response<T>> patch<T>(String path,
      {Object? data,
        Map<String, dynamic>? queryParameters,
        Options? options,
        CancelToken? cancelToken}) {
    return _dio.patch(path,
        data: data, queryParameters: queryParameters, options: options);
  }
}
