import 'package:dawarich/features/tracking/domain/models/location_fix.dart';
import 'package:dawarich/features/tracking/domain/models/tracker_settings.dart';
import 'package:tracelet/tracelet.dart' as tl;

typedef LocationFixHandler = Future<void> Function(LocationFix locationFix);
typedef HeartbeatHandler = Future<void> Function();

abstract interface class ITrackerEngine {
  void setLocationFixHandler(LocationFixHandler? handler);
  void setHeartbeatHandler(HeartbeatHandler? handler);
  Future<tl.State> startTracking(TrackerSettings settings);
  Future<tl.State> stopTracking();
  Future<tl.State> configure(TrackerSettings settings);
  Future<tl.State> updateConfiguration(TrackerSettings settings);
}