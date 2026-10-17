import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 45),
  responseDataCallback: (data) async {
    if (data?['ticket'] != 'MA-TSK-226' ||
        data?['syntheticDataOnly'] != true ||
        !{'windows', 'android'}.contains(data?['platform'])) {
      throw StateError('Falta evidencia nativa sintética T08.');
    }
    final root = await Directory('.tools/226-evidence').create(recursive: true);
    await File('${root.path}/${data!['platform']}.json')
        .writeAsString('${const JsonEncoder.withIndent('  ').convert(data)}\n');
  },
);
