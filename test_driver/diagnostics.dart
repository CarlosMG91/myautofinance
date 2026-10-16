import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 8),
  responseDataCallback: (data) async {
    final captures = data?['diagnosticCaptures'] as Map<String, dynamic>?;
    if (captures == null || captures.length != 5) {
      throw StateError('Faltan capturas nativas del diagnóstico.');
    }
    final directory = await Directory('docs/ep-025/flutter-capturas')
        .create(recursive: true);
    for (final entry in captures.entries) {
      if (!RegExp(r'^(windows|android)-[a-z0-9-]+\.png$').hasMatch(entry.key)) {
        throw StateError('Nombre de captura inválido.');
      }
      await File('${directory.path}/${entry.key}')
          .writeAsBytes(base64Decode(entry.value as String));
    }
    final runtime = data!['runtime'] as Map<String, dynamic>;
    await File('${directory.path}/${runtime['platform']}-origen.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(runtime));
  },
);
