
import 'package:dawarich/core/domain/models/point/api/slim_api_point.dart';
import 'package:dawarich/core/domain/models/point/point_pair.dart';
import 'package:latlong2/latlong.dart';

final class TimelinePointsProcessor {

  List<LatLng> processPoints(
    List<SlimApiPoint> points, {
    int distanceThresholdMeters = 50,
  }) {
    final List<SlimApiPoint> sortedPoints = _sortPoints(points);
    final List<SlimApiPoint> mergedPoints =
        _mergePoints(sortedPoints, distanceThresholdMeters);
    return _parsePoints(mergedPoints);
  }

  List<SlimApiPoint> _sortPoints(List<SlimApiPoint> data) {
    if (data.isEmpty) {
      return [];
    }

    data.sort((a, b) {
      int? timestampA = a.timestamp!;
      int? timestampB = b.timestamp!;

      return timestampA.compareTo(timestampB);
    });

    return data;
  }

  List<SlimApiPoint> _mergePoints(
      List<SlimApiPoint> points, int distanceThresholdMeters) {
    final List<SlimApiPoint> mergedPoints = [];

    if (points.isNotEmpty) {
      LatLng currentPoint = LatLng(double.parse(points[0].latitude!),
          double.parse(points[0].longitude!));
      mergedPoints.add(points[0]);

      for (int i = 1; i < points.length; i++) {
        final nextPoint = LatLng(double.parse(points[i].latitude!),
            double.parse(points[i].longitude!));
        final pointPair = PointPair(currentPoint, nextPoint);
        final double dist = pointPair.calculateDistance();

        if (dist >= distanceThresholdMeters) {
          mergedPoints.add(points[i]);
          currentPoint = nextPoint;
        }
      }
    }

    return mergedPoints;
  }

  List<LatLng> _parsePoints(List<SlimApiPoint> points) {
    return points.map((point) {
      final latitude = double.parse(point.latitude!);
      final longitude = double.parse(point.longitude!);
      return LatLng(latitude, longitude);
    }).toList();
  }

}