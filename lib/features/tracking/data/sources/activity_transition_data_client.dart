import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Polls activity_transition_event.json written by the native
/// MotionSensorManager on both GMS and FOSS builds.
final class ActivityTransitionDataClient {
  final StreamController<void> _controller = StreamController<void>.broadcast();
  bool _started = false;
  Timer? _pollTimer;
  int _lastTransitionTimestamp = 0;

  static const String _transitionFileName = 'activity_transition_event.json';

  void initialize() {
    if (_started) {
      return;
    }
    _started = true;
    _startFilePoll();
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
        debugPrint('[ActivityTransition] Motion transition from file (ts=$timestamp)');
        if (!_controller.isClosed) {
          _controller.add(null);
        }
      }
    } catch (_) {
      // File may not exist yet or may be mid-write.
    }
  }

  Stream<void> watchTransitions() {
    if (!_started) {
      initialize();
    }
    return _controller.stream;
  }

  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _started = false;
    if (!_controller.isClosed) {
      _controller.close();
    }
  }
}
