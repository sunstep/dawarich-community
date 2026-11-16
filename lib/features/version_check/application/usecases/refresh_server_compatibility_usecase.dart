import 'dart:convert';

import 'package:dawarich/core/application/errors/failure.dart';
import 'package:dawarich/features/version_check/application/repository/server_compatibility_store.dart';
import 'package:dawarich/features/version_check/application/repository/version_repository_interfaces.dart';
import 'package:dawarich/features/version_check/domain/server_compatibility_state.dart';
import 'package:dawarich/features/version_check/domain/server_compatibility_status.dart';
import 'package:flutter/foundation.dart';
import 'package:option_result/option_result.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';


/// Use case: decide if the app may proceed given server version + compat rules.
/// - Debug builds: run check but allow bypass on failure (logs errors)
/// - Release builds: enforce check (block on failure)
/// - Network/parse errors: fail open (OK)
/// - Rules use `severity` ("incompatible" | "warning" | "ok") for advisory status
/// - Rules can recommend a server version range with `recommendServer`
final class RefreshServerCompatibilityUseCase {
  final IVersionRepository _versionRepository;
  final IServerCompatibilityStore _store;
  RefreshServerCompatibilityUseCase(this._versionRepository, this._store);

  Future<Result<(), Failure>> call() async {
    final DateTime now = DateTime.now();

    final Result<ServerCompatibilityState, Failure> stateRes =
    await _computeState(now);

    if (stateRes.isOk()) {
      await _store.set(stateRes.unwrap());
      return const Ok(());
    }

    await _store.set(ServerCompatibilityState.unknown(
      checkedAt: now,
      message: 'Could not determine server compatibility.',
      reasonCode: 'CHECK_FAILED',
    ));

    return const Ok(());
  }

  Future<Result<ServerCompatibilityState, Failure>> _computeState(DateTime now) async {
    final Result<String, Failure> versionResult =
    await _versionRepository.getServerVersion();

    if (versionResult.isErr()) {
      return Ok(ServerCompatibilityState.unknown(
        checkedAt: now,
        message: 'Server version not available.',
        reasonCode: 'SERVER_VERSION_UNAVAILABLE',
      ));
    }

    final String versionString = versionResult.unwrap();

    Version serverVersion;
    try {
      serverVersion = Version.parse(versionString);
    } catch (_) {
      return Ok(ServerCompatibilityState.unknown(
        checkedAt: now,
        message: 'Server version is not a valid semver string.',
        reasonCode: 'SERVER_VERSION_INVALID',
      ));
    }

    final Result<String, Failure> compatRulesResult =
    await _versionRepository.getCompatRules();

    if (compatRulesResult.isErr()) {
      return Ok(ServerCompatibilityState.unknown(
        checkedAt: now,
        message: 'Compatibility rules not available.',
        reasonCode: 'RULES_UNAVAILABLE',
      ));
    }

    final String rulesJson = compatRulesResult.unwrap();

    final Map<String, dynamic>? map = _tryDecodeMap(rulesJson);
    if (map == null) {
      return Ok(ServerCompatibilityState.unknown(
        checkedAt: now,
        message: 'Compatibility rules invalid.',
        reasonCode: 'RULES_INVALID_JSON',
      ));
    }

    final packageInfo = await PackageInfo.fromPlatform();
    final rawVersion = packageInfo.version;
    final normalizedVersion = rawVersion.split('-').first;
    final Version appVersion = Version.parse(normalizedVersion);

    final List<dynamic> rulesList = (map['rules'] as List?) ?? const [];
    final Map<String, dynamic> defaultRule =
        (map['default'] as Map<String, dynamic>?) ?? const {};

    final List<Map<String, dynamic>> typedRules =
    rulesList.whereType<Map<String, dynamic>>().toList();

    final Map<String, dynamic>? matchedRule =
    _findMatchingRule(typedRules, appVersion);

    final Map<String, dynamic> rule = matchedRule ?? defaultRule;

    final String messageFromRule = (rule['message'] as String?) ?? '';

    // Parse severity from the rule: "incompatible", "warning", or "ok" (default).
    // This is the severity applied when the server does NOT meet the recommendation.
    final ServerCompatibilityStatus ruleSeverity =
        _parseSeverity(rule['severity'] as String?);

    // Check recommended server version, if present.
    final String? recommendServerStr = rule['recommendServer'] as String?;
    if (recommendServerStr == null || recommendServerStr.trim().isEmpty) {
      // No server recommendation — severity applies directly to this
      // client version (e.g. the default rule blocking old app versions).
      if (ruleSeverity == ServerCompatibilityStatus.ok) {
        return Ok(ServerCompatibilityState(
          status: ServerCompatibilityStatus.ok,
          checkedAt: now,
          appVersion: appVersion.toString(),
          serverVersion: serverVersion.toString(),
          reasonCode: 'NO_SERVER_RECOMMENDATION',
        ));
      }
      return Ok(ServerCompatibilityState(
        status: ruleSeverity,
        checkedAt: now,
        appVersion: appVersion.toString(),
        serverVersion: serverVersion.toString(),
        message: messageFromRule.isNotEmpty
            ? messageFromRule
            : 'This app version has a compatibility issue.',
        reasonCode: 'SEVERITY_NO_SERVER_CHECK',
      ));
    }

    final VersionConstraint? serverConstraint = _tryParseConstraint(recommendServerStr);
    if (serverConstraint == null) {
      return Ok(ServerCompatibilityState(
        status: ServerCompatibilityStatus.warning,
        checkedAt: now,
        appVersion: appVersion.toString(),
        serverVersion: serverVersion.toString(),
        recommendServer: recommendServerStr,
        message: messageFromRule.isNotEmpty
            ? messageFromRule
            : 'Server version recommendation could not be parsed.',
        reasonCode: 'INVALID_SERVER_RECOMMENDATION',
      ));
    }

    final bool serverOk = serverConstraint.allows(serverVersion);
    if (serverOk) {
      // Server meets the recommendation — all good.
      return Ok(ServerCompatibilityState(
        status: ServerCompatibilityStatus.ok,
        checkedAt: now,
        appVersion: appVersion.toString(),
        serverVersion: serverVersion.toString(),
        recommendServer: recommendServerStr,
        reasonCode: 'SERVER_OK',
      ));
    }

    // Server does NOT meet the recommendation — apply the rule's severity.
    return Ok(ServerCompatibilityState(
      status: ruleSeverity == ServerCompatibilityStatus.ok
          ? ServerCompatibilityStatus.warning
          : ruleSeverity,
      checkedAt: now,
      appVersion: appVersion.toString(),
      serverVersion: serverVersion.toString(),
      recommendServer: recommendServerStr,
      message: messageFromRule.isNotEmpty
          ? messageFromRule
          : 'Your server version is not within the recommended range.',
      reasonCode: 'SERVER_VERSION_NOT_RECOMMENDED',
    ));
  }


  Map<String, dynamic>? _tryDecodeMap(String raw) {
    try {
      final sanitized = _removeTrailingCommas(raw);
      final Object? decoded = jsonDecode(sanitized);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      if (kDebugMode) {
        debugPrint('[VersionCheck] Decoded JSON is not a Map: ${decoded.runtimeType}');
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VersionCheck] JSON decode error: $e');
      }
      return null;
    }
  }

  String _removeTrailingCommas(String json) {
    return json.replaceAllMapped(
      RegExp(r',(\s*[}\]])'),
          (match) => match.group(1)!,
    );
  }

  Map<String, dynamic>? _findMatchingRule(
      List<Map<String, dynamic>> typedRules,
      Version appVersion,
      ) {
    Map<String, dynamic>? matchedRule;

    int i = 0;
    while (i < typedRules.length && matchedRule == null) {
      final Map<String, dynamic> item = typedRules[i];

      final Object? clientRangeObj = item['client'];
      final String? clientRangeStr =
      clientRangeObj is String ? clientRangeObj : null;

      if (clientRangeStr != null && clientRangeStr.isNotEmpty) {
        final VersionConstraint? clientConstraint =
        _tryParseConstraint(clientRangeStr);

        final bool isAllowed =
            clientConstraint != null && clientConstraint.allows(appVersion);

        if (isAllowed) {
          matchedRule = item;
        }
      }

      i = i + 1;
    }

    return matchedRule;
  }

  VersionConstraint? _tryParseConstraint(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      return VersionConstraint.parse(raw.trim());
    } catch (_) {
      return null;
    }
  }

  ServerCompatibilityStatus _parseSeverity(String? raw) {
    switch (raw?.toLowerCase().trim()) {
      case 'incompatible':
        return ServerCompatibilityStatus.incompatible;
      case 'warning':
        return ServerCompatibilityStatus.warning;
      case 'ok':
        return ServerCompatibilityStatus.ok;
      default:
        return ServerCompatibilityStatus.ok;
    }
  }
}

