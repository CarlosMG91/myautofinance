import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final captures = data?['redesignCaptures'] as Map<String, dynamic>?;
    if (captures == null || captures.isEmpty) {
      throw StateError('Faltan capturas de los tres tamaños nativos.');
    }
    final platform = captures.keys.first.split('-').first;
    final widths = switch (platform) {
      'windows' => [1440, 1024, 320],
      'android' => [412, 360, 320],
      _ => throw StateError('Plataforma nativa desconocida.'),
    };
    const states = [
      'inicio',
      'estado-detalle',
      'movimiento-borrador',
      'inicio-retorno',
      'presupuesto',
      'presupuesto-detalle',
      'patrimonio',
      'patrimonio-detalle',
      'importar',
      'categorizar-vacio',
      'real-pendiente',
      'indicadores-pendiente',
      'diagnostico-pendiente',
      'inicio-sin-foto',
    ];
    final expected = {
      for (final width in widths)
        for (final state in states)
          '$platform-$width-${width == 320 ? 2 : 1}-$state.png',
      '$platform-${widths.first}-1-movimientos-5004.png',
      for (final state in states) '$platform-320-2-$state-contenido.png',
    };
    if (captures.length != expected.length ||
        !expected.every(captures.containsKey)) {
      throw StateError('Faltan estados o tamaños en las capturas nativas.');
    }
    final results = data?['results'] as List<dynamic>?;
    if (results == null ||
        results.length != 3 ||
        results.any((result) => result['reopened'] != true)) {
      throw StateError('Falta acreditar la reapertura de los tres escenarios.');
    }
    final directory = await Directory('docs/ep-026/validacion-capturas')
        .create(recursive: true);
    final manifest = <Map<String, Object>>[];
    for (final entry in captures.entries) {
      if (!RegExp(
        r'^(windows|android)-(1440|1024|412|360|320)-[12]-[a-z0-9-]+\.png$',
      ).hasMatch(entry.key)) {
        throw StateError('Nombre de captura no permitido.');
      }
      final bytes = base64Decode(entry.value as String);
      final header = bytes.buffer.asByteData();
      final parts = entry.key.split('-');
      final width = int.parse(parts[1]);
      final height = switch (width) {
        1440 => 900,
        1024 => 768,
        412 => 915,
        _ => 800,
      };
      if (bytes.length < 24 ||
          header.getUint32(0) != 0x89504e47 ||
          header.getUint32(16) != width ||
          header.getUint32(20) != height) {
        throw StateError('PNG o dimensiones incorrectos: ${entry.key}.');
      }
      await File('${directory.path}/${entry.key}').writeAsBytes(bytes);
      manifest.add({
        'file': entry.key,
        'width': width,
        'height': height,
        'sha256': sha256.convert(bytes).toString(),
        'origin': 'native-global-journey',
      });
    }
    final imports = data?['importCaptures'] as Map<String, dynamic>?;
    if (imports == null || imports.length != 3) {
      throw StateError(
        'Faltan las capturas del recorrido de importación reutilizado.',
      );
    }
    for (final entry in imports.entries) {
      if (!RegExp(
        r'^native-(windows|android)-(seleccion|resumen|resultado)\.png$',
      ).hasMatch(entry.key)) {
        throw StateError('Nombre de captura de importación no permitido.');
      }
      await File('${directory.path}/import-${entry.key}')
          .writeAsBytes(base64Decode(entry.value as String));
    }
    await File('${directory.path}/$platform-resultados.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(data?['results']),
    );
    await File('${directory.path}/$platform-manifiesto.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'runtime': data?['runtime'],
        'captures': manifest,
        'importCaptures': imports.keys.toList(),
        'limitations':
            'Viewport y escala forzados por el binding; sin marco del SO. '
            'Selector CSV y respuestas Drive sintéticos. Marcadores pendientes '
            'no acreditan integración ni aceptación visual.',
      }),
    );
  },
);
