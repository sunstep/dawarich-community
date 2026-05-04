import 'package:dawarich/core/network/configs/api_config.dart';
import 'package:dawarich/core/network/configs/api_config_manager_interfaces.dart';
import 'package:dawarich/core/shell/drawer/i_api_config_logout.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final class ApiConfigManager implements IApiConfigManager, IApiConfigLogout {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  ApiConfig? _apiConfig;
  ApiConfigManager();
  static const _iOS    = IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  @override
  bool get hasHost => _apiConfig?.hasHost == true;
  @override
  bool get isConfigured => _apiConfig?.isFullyConfigured == true;

  @override
  Future<void> load() async {
    final host = await _secureStorage.read(key: 'host', iOptions: _iOS);
    final apiKey = await _secureStorage.read(key: 'apiKey', iOptions: _iOS);

    if (host != null && host.trim().isNotEmpty) {
      _apiConfig = ApiConfig(host: host.trim(), apiKey: apiKey?.trim());
    } else {
      _apiConfig = null;
    }
  }

  @override
  ApiConfig? get apiConfig => _apiConfig;

  @override
  void createConfig(String host) {
    _apiConfig = ApiConfig(host: host.trim());
  }

  @override
  void setApiKey(String apiKey) {
    final ApiConfig? cfg = _apiConfig;

    if (cfg == null) {
      if (kDebugMode) {
        debugPrint('[ApiConfigManager] Ignoring setApiKey: no config/host set');
      }
      return;
    }

    _apiConfig = cfg.copyWith(apiKey: apiKey.trim());
  }

  @override
  Future<void> storeApiConfig() async {
    final ApiConfig? cfg = _apiConfig;

    if (cfg == null || !cfg.isFullyConfigured) {
      throw Exception('Cannot store incomplete ApiConfigDTO');
    }

    await _secureStorage.write(
        key: 'host',
        value: cfg.host,
        iOptions: _iOS
    );
    await _secureStorage.write(
        key: 'apiKey',
        value: cfg.apiKey,
        iOptions: _iOS
    );
  }

  @override
  Future<void> clearConfiguration() async {
    await _secureStorage.delete(
        key: 'host',
        iOptions: _iOS
    );
    await _secureStorage.delete(
        key: 'apiKey',
        iOptions: _iOS
    );

    _apiConfig = null;
  }

}
