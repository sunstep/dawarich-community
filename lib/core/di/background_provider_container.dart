
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final class BackgroundProviderContainer {
  static Future<ProviderContainer>? _containerFuture;

  static Future<ProviderContainer> ensureInitialized() {
    return _containerFuture ??= _initialize();
  }

  static Future<ProviderContainer> _initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    final ProviderContainer container = ProviderContainer(
      overrides: const [

      ],
    );

    if (kDebugMode) {
      debugPrint('[TraceletBackground] Riverpod container initialized.');
    }

    return container;
  }
}