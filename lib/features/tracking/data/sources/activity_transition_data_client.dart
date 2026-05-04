import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';
import 'package:path_provider/path_provider.dart';

/// Receives activity recognition events via two parallel paths:
///
/// GMS path: subscribes to the flutter_activity_recognition plugin stream.
/// File path: polls activity_transition_event.json written to the app support
/// directory. Works on both flavors; sole active path on FOSS.
///
/// Whichever path detects motion first emits the event. Duplicate events
/// within a short window are deduplicated by timestamp.
final class ActivityTransitionDataClient {
  final FlutterActivityRecognition _recognition =
      FlutterActivityRecognition.instance;

  StreamSubscription<Activity>? _subscription;
  final StreamController<void> _controller = StreamController<void>.broadcast();
  bool _started = false;
  Timer? _retryTimer;
  Timer? _pollTimer;
  int _lastTransitionTimestamp = 0;

  static const int _maxRetries = 5;
  static const String _transitionFileName = 'activity_transition_event.json';

  // True when the FOSS dart-define is set (--dart-define=geolocatorNoPlay=true).
  // On FOSS builds the GMS plugin stream is never subscribed to; only the
  // file-poll path runs.
  static const bool _isFoss = bool.fromEnvironment('geolocatorNoPlay');

  /// Starts both the plugin subscription and the file-poll timer.
  /// Safe to call multiple times; subsequent calls are no-ops.
  void initialize() {
    if (_started) {
      debugPrint('[ActivityRecognition] Already started, skipping');
      return;
    }
    _started = true;
    if (!_isFoss) {
      _subscribe(attempt: 0);
    }
    _startFilePoll();
  }

  void _subscribe({required int attempt}) {
    debugPrint(
      '[ActivityRecognition] Subscribing to activity stream '
      '(attempt ${attempt + 1}/${_maxRetries + 1})',
    );

    try {
      _subscription?.cancel();
      _subscription = _recognition.activityStream.listen(
        (activity) {
          debugPrint(
            '[ActivityRecognition] Activity: ${activity.type} '
            '(confidence: ${activity.confidence})',
          );

          if (_isLocomotion(activity.type)) {
            debugPrint('[ActivityRecognition] Locomotion detected via plugin stream');
            if (!_controller.isClosed) {
              _controller.add(null);
            }
          }
        },
        onError: (e) {
          debugPrint('[ActivityRecognition] Stream error: $e');
          _subscription?.cancel();
          _subscription = null;
          _scheduleRetry(attempt);
        },
      );
    } catch (e) {
      // receiveBroadcastStream() can throw synchronously on FOSS builds.
      debugPrint('[ActivityRecognition] Subscribe failed: $e');
      _scheduleRetry(attempt);
    }
  }

  void _scheduleRetry(int attempt) {
    if (attempt >= _maxRetries) {
      debugPrint(
        '[ActivityRecognition] Plugin stream unavailable after $attempt retries. '
        'Relying on file-poll path.',
      );
      return;
    }

    final delaySec = 2 * (1 << attempt);
    debugPrint(
      '[ActivityRecognition] Retrying plugin stream in ${delaySec}s '
      '(attempt ${attempt + 2}/${_maxRetries + 1})',
    );

    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: delaySec), () {
      if (_controller.isClosed) {
        return;
      }
      _subscribe(attempt: attempt + 1);
    });
  }

  void _startFilePoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pollTransitionFile();
    });
  }

  Future<void> _pollTransitionFile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_transitionFileName');
      if (!file.existsSync()) {
        return;
      }

      final content = file.readAsStringSync();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final timestamp = json['timestamp'] as int?;

      if (timestamp != null && timestamp > _lastTransitionTimestamp) {
        _lastTransitionTimestamp = timestamp;
        debugPrint(
          '[ActivityRecognition] Motion transition from file poll (ts=$timestamp)',
        );
        if (!_controller.isClosed) {
          _controller.add(null);
        }
      }
    } catch (_) {
      // File may not exist yet or may be mid-write.
    }
  }

  /// Returns a broadcast stream that emits whenever locomotion is detected.
  Stream<void> watchTransitions() {
    if (!_started) {
      initialize();
    }

    debugPrint('[ActivityRecognition] Subscribing to motion transitions');
    return _controller.stream;
  }

  void dispose() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _started = false;
    if (!_controller.isClosed) {
      _controller.close();
    }
  }

  static bool _isLocomotion(ActivityType type) {
    return switch (type) {
      ActivityType.WALKING => true,
      ActivityType.RUNNING => true,
      ActivityType.ON_BICYCLE => true,
      ActivityType.IN_VEHICLE => true,
      ActivityType.STILL => false,
      ActivityType.UNKNOWN => false,
    };
  }
}
