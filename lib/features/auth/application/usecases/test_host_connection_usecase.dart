import 'package:dawarich/core/application/errors/failure.dart';
import 'package:dawarich/features/auth/application/repositories/connect_repository_interfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:option_result/result.dart';

final class TestHostConnectionUseCase {
  final IConnectRepository _connectRepository;

  TestHostConnectionUseCase(this._connectRepository);

  bool _hasProtocol(String host) {
    final lowerHost = host.toLowerCase();
    return lowerHost.startsWith("http://") || lowerHost.startsWith("https://");
  }

  /// Returns Ok(normalizedHostWithProtocol) when reachable.
  /// Returns Err(Failure) otherwise.
  Future<Result<String, Failure>> call(String host) async {
    final normalizedInput = host.trim();

    if (normalizedInput.isEmpty) {
      return Err(
        Failure(
          kind: FailureKind.validation,
          code: 'HOST_EMPTY',
          message: 'Host is empty.',
          context: const {'where': 'TestHostConnectionUseCase'},
        ),
      );
    }

    var cleaned = normalizedInput;

    // remove trailing slashes
    cleaned = cleaned.replaceAll(RegExp(r'/+$'), '');

    // User provided protocol -> test as-is
    if (_hasProtocol(cleaned)) {
      final ok = await _connectRepository.testHost(cleaned);

      if (ok) {
        return Ok(cleaned);
      }

      return Err(
        Failure(
          kind: FailureKind.network,
          code: 'HOST_UNREACHABLE',
          message: 'Unable to reach server.',
          context: {
            'where': 'TestHostConnectionUseCase',
            'attempted': cleaned,
          },
        ),
      );
    }

    // No protocol -> try https then http
    final httpsUrl = "https://$cleaned";
    final okHttps = await _connectRepository.testHost(httpsUrl);

    if (okHttps) {
      return Ok(httpsUrl);
    }

    if (kDebugMode) {
      debugPrint("[TestHost] HTTPS failed, trying HTTP for: $cleaned");
    }

    final httpUrl = "http://$cleaned";
    final okHttp = await _connectRepository.testHost(httpUrl);

    if (okHttp) {
      return Ok(httpUrl);
    }

    return Err(
      Failure(
        kind: FailureKind.network,
        code: 'HOST_UNREACHABLE',
        message: 'Unable to reach server via HTTPS or HTTP.',
        context: {
          'where': 'TestHostConnectionUseCase',
          'attempted': [httpsUrl, httpUrl],
        },
      ),
    );
  }
}
