import 'package:dawarich/core/di/background_provider_container.dart';
import 'package:dawarich/core/di/providers/app_providers.dart';
import 'package:dawarich/features/tracking/application/services/point_automation_service.dart';
import 'package:dawarich/features/tracking/domain/models/location_fix.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracelet/tracelet.dart' as tl;

import 'dart:async';

@pragma('vm:entry-point')
Future<void> dawarichTraceletHeadlessTask(tl.HeadlessEvent event) async {
  try {
    await _handleDawarichTraceletHeadlessEvent(event);
  } catch (error, stackTrace) {
    if (kDebugMode) {
      debugPrint('[TraceletHeadless] Unhandled failure: $error');
      debugPrint('$stackTrace');
    }
  }
}

void debugTraceletHeadlessEnvelope(tl.HeadlessEvent event) {
  if (!kDebugMode) return;

  debugPrint('[TraceletHeadless] envelope runtimeType=${event.runtimeType}');
  debugPrint('[TraceletHeadless] envelope toString=$event');

  Object? read(String label, Object? Function() getter) {
    try {
      final value = getter();
      debugPrint(
        '[TraceletHeadless] $label=$value '
            'runtimeType=${value.runtimeType}',
      );
      return value;
    } catch (error) {
      debugPrint('[TraceletHeadless] $label unavailable: $error');
      return null;
    }
  }

  final dynamic dynamicEvent = event;

  read('event.name', () => dynamicEvent.name);
  read('event.type', () => dynamicEvent.type);
  read('event.event', () => dynamicEvent.event);
  read('event.payload', () => dynamicEvent.payload);
  read('event.data', () => dynamicEvent.data);
  read('event.location', () => dynamicEvent.location);
  read('event.toMap()', () => dynamicEvent.toMap());
  read('event.toJson()', () => dynamicEvent.toJson());
}

Future<void> _handleDawarichTraceletHeadlessEvent(
    tl.HeadlessEvent event,
    ) async {
  try {
    final Map<String, Object?> envelope =
    _asStringObjectMap((event as dynamic).toMap());

    final String? name = envelope['name']?.toString();
    final Map<String, Object?> payload =
    _asStringObjectMap(envelope['event']);

    if (name == 'providerchange' || name == 'motionchange') {
      if (kDebugMode) {
        debugPrint('[TraceletHeadless] Ignoring Tracelet event: $name');
      }
      return;
    }

    final ProviderContainer container =
    await BackgroundProviderContainer.ensureInitialized();

    final int? userId = await container.read(sessionUserIdProvider.future);

    if (userId == null) {
      if (kDebugMode) {
        debugPrint('[TraceletHeadless] No session user available; skipping.');
      }
      return;
    }

    if (name == 'location') {

      final LocationFix? locationFix =
      _mapTraceletHeadlessLocationPayload(payload);

      if (locationFix == null) {
        if (kDebugMode) {
          debugPrint(
            '[TraceletHeadless] Dropping invalid location payload: $payload',
          );
        }
        return;
      }

      final PointAutomationService pointAutomationService =
      await container.read(pointAutomationServiceProvider.future);

      await pointAutomationService.handleTraceletLocationFix(
        userId: userId,
        locationFix: locationFix,
      );

      if (kDebugMode) {
        debugPrint(
          '[TraceletHeadless] Location processed: '
              'lat=${locationFix.latitude}, '
              'lon=${locationFix.longitude}, '
              'timestamp=${locationFix.timestampUtc}',
        );
      }

      return;
    }

    if (name == 'heartbeat') {
      final PointAutomationService pointAutomationService =
      await container.read(pointAutomationServiceProvider.future);

      await pointAutomationService.handleTraceletHeartbeat(userId: userId);
      return;
    }

    if (kDebugMode) {
      debugPrint(
        '[TraceletHeadless] Unsupported Tracelet headless event: '
            'name=$name, type=${event.runtimeType}, payload=$payload',
      );
    }
  } catch (error, stackTrace) {
    if (kDebugMode) {
      debugPrint('[TraceletHeadless] FAILED: $error');
      debugPrint('$stackTrace');
    }
  }
}

LocationFix? _mapTraceletHeadlessLocationPayload(
    Map<String, Object?> payload,
    ) {
  final Map<String, Object?> coords =
  _asStringObjectMap(payload['coords']);

  final double? latitude = _asDouble(coords['latitude']);
  final double? longitude = _asDouble(coords['longitude']);
  final double? accuracy = _asDouble(coords['accuracy']);

  if (latitude == null || longitude == null || accuracy == null) {
    if (kDebugMode) {
      debugPrint(
        '[TraceletHeadless] Invalid coords: '
            'lat=$latitude, lon=$longitude, acc=$accuracy, coords=$coords',
      );
    }
    return null;
  }

  return LocationFix(
    latitude: latitude,
    longitude: longitude,
    timestampUtc: _asUtcDateTime(payload['timestamp']),
    hAccuracyMeters: accuracy,
    altitudeMeters: _asDouble(coords['altitude']) ?? 0.0,
    altitudeAccuracyMeters: _asDouble(coords['altitudeAccuracy']) ?? -1.0,
    speedMps: _asDouble(coords['speed']) ?? 0.0,
    speedAccuracyMps: _asDouble(coords['speedAccuracy']) ?? -1.0,
    headingDegrees: _asDouble(coords['heading']) ?? 0.0,
    headingAccuracyDegrees: _asDouble(coords['headingAccuracy']) ?? -1.0,
    provider: payload['locationSource']?.toString() ?? 'unknown',
    isMocked: payload['mock'] == true,
  );
}

Map<String, Object?> _asStringObjectMap(Object? value) {
  if (value is! Map) return const <String, Object?>{};

  return value.map(
        (key, value) => MapEntry(key.toString(), value),
  );
}

double? _asDouble(Object? value) {
  return switch (value) {
    final num number => number.toDouble(),
    final String text => double.tryParse(text),
    _ => null,
  };
}

DateTime _asUtcDateTime(Object? value) {
  if (value is String) {
    return DateTime.tryParse(value)?.toUtc() ?? DateTime.now().toUtc();
  }

  return DateTime.now().toUtc();
}