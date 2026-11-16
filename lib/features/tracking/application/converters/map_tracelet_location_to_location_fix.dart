import 'package:dawarich/features/tracking/domain/models/location_fix.dart';
import 'package:tracelet/tracelet.dart' as tl;

LocationFix mapTraceletLocationToLocationFix(tl.Location location) {
  final tl.Coords coords = location.coords;

  return LocationFix(
    latitude: coords.latitude,
    longitude: coords.longitude,
    timestampUtc: DateTime.tryParse(location.timestamp)?.toUtc() ??
        DateTime.now().toUtc(),
    hAccuracyMeters: coords.accuracy,
    altitudeMeters: coords.altitude,
    altitudeAccuracyMeters: coords.altitudeAccuracy,
    speedMps: coords.speed,
    speedAccuracyMps: coords.speedAccuracy,
    headingDegrees: coords.heading,
    headingAccuracyDegrees: coords.headingAccuracy,
    provider: location.locationSource,
    isMocked: location.isMock,
  );
}