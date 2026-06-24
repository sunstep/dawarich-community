//
// import 'dart:async';
//
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_background_service/flutter_background_service.dart';
//
// import 'background_tracking_service.dart';
//
//
// @pragma('vm:entry-point')
// void backgroundTrackingEntry(ServiceInstance backgroundService) {
//
//   if (kDebugMode) {
//     debugPrint('[Background] Entry point reached');
//   }
//
//   WidgetsFlutterBinding.ensureInitialized();
//
//
//   BackgroundTrackingEntry.registerListeners(backgroundService);
//   if (kDebugMode) {
//     debugPrint('[Background] Listeners registered (stopService, restartTracking)');
//   }
//   backgroundService.invoke('ready');
//
//   unawaited(() async {
//     try {
//       await BackgroundTrackingEntry.checkBackgroundTracking(backgroundService);
//     } catch (e, s) {
//       debugPrint('[Background] Fatal in checkBackgroundTracking: $e\n$s');
//       await BackgroundTrackingEntry.shutdown(backgroundService, 'fatal error');
//     }
//   }());
// }