import 'package:dawarich/features/tracking/domain/enum/battery_state.dart';
import 'package:dawarich/features/tracking/domain/enum/connectivity_kind.dart';

abstract interface class IHardwareRepository {

  Future<String> getDeviceModel();

  Future<BatteryState> getBatteryState();
  Future<double> getBatteryLevel();

  /// Emits the current [BatteryState] whenever the charging state changes.
  Stream<BatteryState> watchBatteryState();

  Future<String?> getWiFiStatus();

  /// Emits the current [ConnectivityKind] whenever the network state changes.
  Stream<ConnectivityKind> watchConnectivity();

  /// Emits a void event whenever the OS detects a locomotion transition
  /// (e.g. STILL -> ON_FOOT, STILL -> IN_VEHICLE).
  ///
  /// On GMS builds this uses the Activity Transition API (zero polling cost).
  /// On FOSS builds it falls back to TYPE_SIGNIFICANT_MOTION.
  ///
  /// Returns Stream.empty if the required permission is not granted or the
  /// platform doesn't support motion detection.
  Stream<void> watchMotionTransitions();
}
