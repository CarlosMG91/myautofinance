import 'package:integration_test/integration_test_driver.dart';

import 'dart:convert';
import 'dart:io';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final captures = data?['catalogCaptures'] as Map<String, dynamic>?;
    if (captures == null || captures.isEmpty) {
      throw StateError('El recorrido no devolvió sus capturas nativas.');
    }
    final directory = await Directory('docs/ep-026/catalogos-capturas')
        .create(recursive: true);
    for (final entry in captures.entries) {
      if (!RegExp(r'^(windows|android)-[a-z]+-[12]\.png$')
          .hasMatch(entry.key)) {
        throw StateError('Nombre de captura inesperado.');
      }
      await File('${directory.path}/${entry.key}')
          .writeAsBytes(base64Decode(entry.value as String));
    }
  },
);
