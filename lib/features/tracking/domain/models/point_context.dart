
import 'package:dawarich/features/tracking/domain/enum/battery_state.dart';
import 'package:dawarich/features/tracking/domain/enum/tracking_mode.dart';

final class PointContext {

  /// User chosen device identifier for points.
  final String deviceId;

  /// Id for grouping points into tracks.
  final String? trackId;

  final String? wifi;

  /// Battery state at capture time.
  final BatteryState batteryState;

  /// Battery level from 0.0 to 1.0.
  final double batteryLevel;



  /// Optional: platform identifier ("android", "ios") if useful for debugging/analytics.
  final String? platform;

  /// Optional: source label to aid debugging (e.g. "foreground", "background").
  final String? source;

  const PointContext({
    required this.deviceId,
    required this.trackId,
    required this.wifi,
    required this.batteryState,
    required this.batteryLevel,
    this.platform,
    this.source,
  });
}