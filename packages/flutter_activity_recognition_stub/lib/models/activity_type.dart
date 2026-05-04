enum ActivityType {
  IN_VEHICLE,
  ON_BICYCLE,
  RUNNING,
  STILL,
  WALKING,
  UNKNOWN;

  static ActivityType fromString(String? value) =>
      ActivityType.values.firstWhere(
        (e) => e.toString() == 'ActivityType.$value',
        orElse: () => ActivityType.UNKNOWN,
      );
}

