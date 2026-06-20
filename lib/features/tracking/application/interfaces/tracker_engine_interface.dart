import 'package:dawarich/features/tracking/domain/models/tracker_settings.dart';
import 'package:tracelet/tracelet.dart' as tl;

abstract interface class ITrackerEngine {
  Future<tl.State> startTracking(TrackerSettings settings);
  Future<tl.State> stopTracking();
  Future<tl.State> configure(TrackerSettings settings);
  Future<tl.State> updateConfiguration(TrackerSettings settings);
}