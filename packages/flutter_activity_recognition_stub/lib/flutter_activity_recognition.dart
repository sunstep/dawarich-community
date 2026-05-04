/// Stub models — mirrors the real package's public API so imports compile.
library;

export 'models/activity_type.dart';
export 'models/activity_confidence.dart';
export 'models/activity.dart';

import 'dart:async';
import 'models/activity.dart';

/// Stub that matches the real FlutterActivityRecognition public API.
/// activityStream always returns an empty stream; no GMS code is involved.
class FlutterActivityRecognition {
  FlutterActivityRecognition._internal();

  static final instance = FlutterActivityRecognition._internal();

  /// Never emits; the FOSS build relies on the file-poll path instead.
  Stream<Activity> get activityStream => const Stream.empty();
}

