import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 10),
  responseDataCallback: (data) async {
    final captures = data?['indicatorCaptures'] as Map<String, dynamic>?;
    if (captures == null || captures.length != 13) {
      throw StateError(
        'Faltan capturas nativas del recorrido y sus siete estados.',
      );
    }
    final directory = await Directory('docs/ep-023/flutter-capturas')
        .create(recursive: true);
    final runtime = data!['runtime'] as Map<String, dynamic>;
    for (final entry in captures.entries) {
      if (!RegExp(r'^(windows|android)-[a-z0-9-]+\.png$').hasMatch(entry.key)) {
        throw StateError('Nombre de captura inválido.');
      }
      await File('${directory.path}/${entry.key}')
          .writeAsBytes(base64Decode(entry.value as String));
    }
    await File('${directory.path}/${runtime['platform']}-origen.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(runtime));
  },
);
