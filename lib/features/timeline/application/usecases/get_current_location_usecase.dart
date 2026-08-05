import 'package:geolocator/geolocator.dart';

final class GetCurrentLocationUseCase {
  Future<Position?> call() async {
    try {
      bool serviceEnabled;
      LocationPermission permission;

      serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        return null;
      }

      permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      Position position = await Geolocator.getCurrentPosition();

      return position;
    } catch (e) {
      // iOS geolocator crash workaround
      debugPrint('[GetCurrentLocationUseCase] Geolocator error: $e');
      return null;
    }
  }
}
