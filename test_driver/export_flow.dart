import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 15),
  responseDataCallback: (data) async {
    if (data?['syntheticDataOnly'] != true ||
        !{'windows', 'android'}.contains(data?['platform'])) {
      throw StateError('Falta evidencia nativa sintética.');
    }
    final directory = await Directory('.tools/224-evidence')
        .create(recursive: true);
    await File('${directory.path}/${data!['platform']}.json')
        .writeAsString('${const JsonEncoder.withIndent('  ').convert(data)}\n');
  },
);
