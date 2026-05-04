import 'dart:io';

import 'package:battery_plus/battery_plus.dart' as battery_plus;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dawarich/features/tracking/data/sources/activity_transition_data_client.dart';
import 'package:dawarich/features/tracking/data/sources/device_data_client.dart';
import 'package:dawarich/features/tracking/data/sources/connectivity_data_client.dart';
import 'package:dawarich/features/tracking/application/repositories/hardware_repository_interfaces.dart';
import 'package:dawarich/features/tracking/domain/enum/battery_state.dart';
import 'package:dawarich/features/tracking/domain/enum/connectivity_kind.dart';
import 'package:network_info_plus/network_info_plus.dart';

final class HardwareRepository implements IHardwareRepository {
  final DeviceDataClient _deviceDataClient;
  final ConnectivityDataClient _wiFiDataClient;
  final ActivityTransitionDataClient _activityTransitionClient;

  HardwareRepository(
    this._deviceDataClient,
    this._wiFiDataClient,
    this._activityTransitionClient,
  );

  @override
  Future<String> getDeviceModel() async {
    if (Platform.isAndroid) {
      return _deviceDataClient.getAndroidDeviceModel();
    } else if (Platform.isIOS) {
      return _deviceDataClient.getIOSDeviceModel();
    } else {
      return "Unknown";
    }
  }

  @override
  Future<BatteryState> getBatteryState() async {
    final battery_plus.Battery battery = battery_plus.Battery();
    final battery_plus.BatteryState state = await battery.batteryState;
    return _mapBatteryState(state);
  }

  BatteryState _mapBatteryState(battery_plus.BatteryState state) {
    return switch (state) {
      battery_plus.BatteryState.charging => BatteryState.charging,
      battery_plus.BatteryState.discharging => BatteryState.discharging,
      battery_plus.BatteryState.full => BatteryState.full,
      battery_plus.BatteryState.connectedNotCharging => BatteryState.connectedNotCharging,
      battery_plus.BatteryState.unknown => BatteryState.unknown,
    };
  }

  @override
  Future<double> getBatteryLevel() async {
    return await battery_plus.Battery().batteryLevel / 100;
  }

  @override
  Stream<BatteryState> watchBatteryState() {
    return battery_plus.Battery().onBatteryStateChanged.map(_mapBatteryState);
  }

  @override
  Future<String?> getWiFiStatus() async {
    List<ConnectivityResult> connectionList =
        await _wiFiDataClient.getWiFiStatus();

    if (connectionList.contains(ConnectivityResult.wifi)) {
      try {
        final NetworkInfo wifiInfo = NetworkInfo();
        final String? rawSSID = await wifiInfo.getWifiName();

        if (rawSSID == null) return null;

        // Clean the output by removing outer quotes.
        if (rawSSID.startsWith('"') && rawSSID.endsWith('"')) {
          return rawSSID.substring(1, rawSSID.length - 1);
        }
        return rawSSID;
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  @override
  Stream<ConnectivityKind> watchConnectivity() {
    return Connectivity().onConnectivityChanged.map((results) {
      if (results.contains(ConnectivityResult.wifi)) return ConnectivityKind.wifi;
      if (results.contains(ConnectivityResult.ethernet)) return ConnectivityKind.ethernet;
      if (results.contains(ConnectivityResult.vpn)) return ConnectivityKind.vpn;
      if (results.contains(ConnectivityResult.mobile)) return ConnectivityKind.mobile;
      if (results.contains(ConnectivityResult.other)) return ConnectivityKind.other;
      return ConnectivityKind.none;
    });
  }

  @override
  Stream<void> watchMotionTransitions() {
    return _activityTransitionClient.watchTransitions();
  }
}
