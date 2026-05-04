import 'activity_confidence.dart';
import 'activity_type.dart';

class Activity {
  final ActivityType type;
  final ActivityConfidence confidence;

  const Activity(this.type, this.confidence);

  factory Activity.fromJson(Map<String, dynamic> json) {
    return Activity(
      ActivityType.fromString(json['type'] as String?),
      ActivityConfidence.fromString(json['confidence'] as String?),
    );
  }
}

