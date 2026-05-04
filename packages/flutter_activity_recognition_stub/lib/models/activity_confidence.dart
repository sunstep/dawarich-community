enum ActivityConfidence {
  HIGH,
  MEDIUM,
  LOW;

  static ActivityConfidence fromString(String? value) =>
      ActivityConfidence.values.firstWhere(
        (e) => e.toString() == 'ActivityConfidence.$value',
        orElse: () => ActivityConfidence.LOW,
      );
}

