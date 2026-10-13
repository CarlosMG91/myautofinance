import 'package:integration_test/integration_test_driver.dart';

import 'dart:convert';
import 'dart:io';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final captures = data?['importCaptures'] as Map<String, dynamic>?;
    if (captures == null || captures.length != 3) {
      throw StateError('El recorrido no devolvió las tres capturas nativas.');
    }
    final directory = await Directory('docs/ep-026/importaciones-capturas')
        .create(recursive: true);
    for (final entry in captures.entries) {
      if (!RegExp(
        r'^native-(windows|android)-(seleccion|resumen|resultado)\.png$',
      ).hasMatch(entry.key)) {
        throw StateError('Nombre de captura inesperado.');
      }
      await File('${directory.path}/${entry.key}')
          .writeAsBytes(base64Decode(entry.value as String));
    }
  },
);
