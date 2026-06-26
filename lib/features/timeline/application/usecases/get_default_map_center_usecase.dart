import 'package:country/country.dart';
import 'package:device_region/device_region.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

final class GetDefaultMapCenterUseCase {
  GetDefaultMapCenterUseCase();

  Future<LatLng> call() async {
    // Try real GPS position first
    try {
      if (await Geolocator.isLocationServiceEnabled()) {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }

        if (permission != LocationPermission.denied &&
            permission != LocationPermission.deniedForever) {
          try {
            final current = await Geolocator.getCurrentPosition();
            return LatLng(current.latitude, current.longitude);
          } catch (_) {
            final last = await Geolocator.getLastKnownPosition();
            if (last != null) {
              return LatLng(last.latitude, last.longitude);
            }
          }
        }
      }
    } catch (e) {
      // iOS geolocator crash workaround - fall through to SIM/locale fallback
      debugPrint('[GetDefaultMapCenterUseCase] Geolocator error: $e');
    }

    // GPS failed → fallback to SIM/locale-based default
    String? countryCode = await DeviceRegion.getSIMCountryCode();

    if (countryCode == null) {
      final dispatcher = WidgetsBinding.instance.platformDispatcher;
      final Locale locale = dispatcher.locale;
      countryCode = locale.countryCode ?? '';
    }

    return _centroidForIso(countryCode);
  }

  LatLng _centroidForIso(String iso) {
    final c = Countries.values.firstWhere(
      (e) => e.alpha2.toUpperCase() == iso.toUpperCase(),
      orElse: () => Countries.values.first, // fallback country
    );
    final coord = c.geo.coordinate;
    return LatLng(coord.latitude, coord.longitude);
  }
}
