

import 'dart:io';

import 'package:dawarich/core/network/errors/remote_request_failure.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

final class ErrorInterceptor extends Interceptor {


  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.type == DioExceptionType.cancel) {
      return handler.next(err);
    }

    final RemoteRequestFailure failure = _map(err);

    if (kDebugMode) {
      debugPrint('--- Dio raw error (interceptor) ---');
      debugPrint('type: ${err.type}');
      debugPrint('message: ${err.message}');
      debugPrint('error: ${err.error}');
      debugPrint('errorType: ${err.error.runtimeType}');
      debugPrint('uri: ${err.requestOptions.uri}');
      debugPrint('method: ${err.requestOptions.method}');
      debugPrint('headers: ${err.requestOptions.headers}');
      debugPrint('query: ${err.requestOptions.queryParameters}');
      debugPrint('status: ${err.response?.statusCode}');
      debugPrint('responseHeaders: ${err.response?.headers.map}');
      debugPrint('responseData: ${err.response?.data}');
      debugPrint('stack: ${err.stackTrace}');
      debugPrint('--- RemoteRequestFailure ---');
      debugPrint(failure.debugString);
    }

    handler.next(err.copyWith(
      error: failure,
      message: failure.userMessage,
    ));
  }

  RemoteRequestFailure _map(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return TimeoutFailure(technical: e.message);

      case DioExceptionType.badCertificate:
        return TlsFailure(technical: e.message);

      case DioExceptionType.connectionError:
        final u = e.error;
        if (u is SocketException) return OfflineFailure(technical: u.message);
        if (u is HandshakeException || u is TlsException) {
          return TlsFailure(technical: u.toString());
        }
        return OfflineFailure(technical: e.message);

      case DioExceptionType.badResponse:
        final res = e.response;
        final code = res?.statusCode;
        final msg  = _serverMessage(res);
        switch (code) {
          case 401: return UnauthorizedFailure(technical: msg);
          case 403: return ForbiddenFailure(technical: msg);
          case 404: return NotFoundFailure(technical: msg);
          case 409: return ConflictFailure(technical: msg);
          case 422: return ValidationFailure(
            fieldErrors: _validation(res),
            serverMessage: msg,
            statusCode: code,
          );
        }
        if (code != null && code >= 500) {
          return ServerFailure(statusCode: code, serverMessage: msg);
        }
        return UnexpectedFailure(technical: msg, statusCode: code);

      case DioExceptionType.cancel:
        return UnexpectedFailure(technical: 'Request was cancelled.');

      case DioExceptionType.unknown:
        return UnexpectedFailure(technical: e.message);


      case DioExceptionType.transformTimeout:
        return UnexpectedFailure(technical: 'Request transform timeout.');
    }
  }

  String? _serverMessage(Response? res) {
    final d = res?.data;
    if (d is Map) {
      final msg = (d['message'] ?? d['error'])?.toString();
      if (msg != null && msg.isNotEmpty) return msg;
      final errors = d['errors'];
      if (errors is String && errors.isNotEmpty) return errors;
      if (errors is List && errors.isNotEmpty) return errors.join(', ');
    } else if (d is String && d.isNotEmpty) {
      return d;
    }
    return null;
  }

  Map<String, List<String>> _validation(Response? res) {
    final d = res?.data;
    if (d is Map && d['errors'] is Map) {
      final src = (d['errors'] as Map);
      return Map.unmodifiable({
        for (final e in src.entries)
          e.key.toString(): switch (e.value) {
            List l => List<String>.unmodifiable(l.map((v) => v.toString())),
            Object v => List<String>.unmodifiable([v.toString()]),
            _ => const <String>[],
          }
      });
    }
    return const {};
  }
}