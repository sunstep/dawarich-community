
import 'package:dawarich/core/di/background_provider_container.dart';
import 'package:dawarich/core/di/providers/app_providers.dart';
import 'package:dawarich/features/tracking/application/converters/map_tracelet_location_to_location_fix.dart';
import 'package:dawarich/features/tracking/application/services/point_automation_service.dart';
import 'package:dawarich/features/tracking/domain/models/location_fix.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracelet/tracelet.dart' as tl;

@pragma('vm:entry-point')
Future<void> dawarichTraceletHeadlessTask(tl.HeadlessEvent event) async {

  final ProviderContainer container =
  await BackgroundProviderContainer.ensureInitialized();

  final userId = container.read(currentUserIdProvider);

  final PointAutomationService pointAutomationService =
  await container.read(pointAutomationServiceProvider.future);

  if (event case tl.Location location) {
    final LocationFix locationFix = mapTraceletLocationToLocationFix(location);

    await pointAutomationService.handleTraceletLocationFix(
      userId: userId,
      locationFix: locationFix,
    );

    return;
  }

  if (event case tl.HeartbeatEvent()) {
    await pointAutomationService.handleTraceletHeartbeat(
      userId: userId,
    );

    return;
  }

  if (kDebugMode) {
    debugPrint(
      '[TraceletHeadless] Unsupported Tracelet headless event: '
          '${event.runtimeType}',
    );
  }

}