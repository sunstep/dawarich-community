/// Abstract precision levels that are provider-agnostic.
/// Data layer maps these to Geolocator / platform settings.
///
/// Code values match the old geolocator LocationAccuracy indices
/// for backward compatibility with existing database values.
enum LocationPrecision {

  powerSave(0), // LocationAccuracy.lowest — passive accuracy
  lowPower(1),  // Was LocationAccuracy.low (index 1)
  balanced(2),  // Was LocationAccuracy.medium (index 2)
  high(3),      // Was LocationAccuracy.high (index 3)
  best(4);      // Was LocationAccuracy.best (index 4)

  final int code;
  const LocationPrecision(this.code);

  static LocationPrecision fromCode(int code) {
    for (final v in LocationPrecision.values) {
      if (v.code == code) {
        return v;
      }
    }
    // Default fallback for unknown codes
    return LocationPrecision.high;
  }
}