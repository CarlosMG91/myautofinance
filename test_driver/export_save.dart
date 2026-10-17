import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 15),
  responseDataCallback: (data) async {
    final platform = data?['platform'];
    if (!{'windows', 'android'}.contains(platform) ||
        data?['syntheticDataOnly'] != true) {
      throw StateError('Falta evidencia nativa sintética.');
    }
    final directory = await Directory('.tools/222-evidence')
        .create(recursive: true);
    await File('${directory.path}/$platform.json')
        .writeAsString('${const JsonEncoder.withIndent('  ').convert(data)}\n');
  },
);
