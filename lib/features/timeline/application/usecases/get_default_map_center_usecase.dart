import 'package:country/country.dart';
import 'package:device_region/device_region.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

final class GetDefaultMapCenterUseCase {
  GetDefaultMapCenterUseCase();

  Future<LatLng> call() async {
    // 1. Last known position — instantaneous, no GPS warm-up needed.
    //    This is the correct initial centre 99 % of the time.
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return LatLng(last.latitude, last.longitude);
      }
    } catch (_) {}

    // 2. SIM / locale centroid — fast, no GPS required.
    //    (Removed the slow getCurrentPosition() call that could block for
    //    several seconds when no last-known fix was available.)
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
      orElse: () => Countries.values.first,
    );
    final coord = c.geo.coordinate;
    return LatLng(coord.latitude, coord.longitude);
  }
}