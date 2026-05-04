import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Polls activity_transition_event.json written by the native
/// MotionSensorManager on both GMS and FOSS builds.
///
/// The poll timer is started on the first stream subscription and stopped
/// when all subscriptions are cancelled, so it only runs while something is
/// actively listening (i.e., while passive-mode wakeups are needed).
final class ActivityTransitionDataClient {
  StreamController<void>? _controller;
  Timer? _pollTimer;
  int _lastTransitionTimestamp = 0;

  static const String _transitionFileName = 'activity_transition_event.json';

  Stream<void> watchTransitions() {
    _ensureController();
    return _controller!.stream;
  }

  void _ensureController() {
    if (_controller != null && !_controller!.isClosed) {
      return;
    }

    _controller = StreamController<void>.broadcast(
      onListen: _startFilePoll,
      onCancel: _stopFilePoll,
    );
  }

  void _startFilePoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pollTransitionFile();
    });
  }

  void _stopFilePoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
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
        if (kDebugMode) {
          debugPrint('[ActivityTransition] Motion transition from file (ts=$timestamp)');
        }
        final ctrl = _controller;
        if (ctrl != null && !ctrl.isClosed) {
          ctrl.add(null);
        }
      }
    } catch (_) {
      // File may not exist yet or may be mid-write.
    }
  }

  void dispose() {
    _stopFilePoll();
    _controller?.close();
    _controller = null;
  }
}
