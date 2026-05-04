

import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final class DbKeyProvider {

  final FlutterSecureStorage _ss = const FlutterSecureStorage();
  static const _k = 'db_key_v1';

  Future<String> getOrCreateHexKey() async {

    final String? e = await _ss.read(key: _k);

    if (e != null && e.isNotEmpty) {
      return e;
    }

    final Random rnd = Random.secure();
    final List<int> bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    final String hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    await _ss.write(
      key: _k,
      value: hex,
    );
    return hex;
  }

}