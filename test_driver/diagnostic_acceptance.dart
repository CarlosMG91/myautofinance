import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 10),
  responseDataCallback: (data) async {
    const requiredStages = {
      'csv-repetido-sin-altas',
      'categorizado-resultado-obsoleto',
      'pendiente-resuelto-avisos-conservados',
      'foto-incompleta-sin-acarreo',
      'foto-completa-cero-valido-colchon-2-07',
      'correccion-febrero-colchon-2-10',
      'recuperacion-y-repeticion-explicita',
    };
    final platform = data?['platform'];
    final stages = data?['stages'] as Map<String, dynamic>?;
    final csvHash = sha256
        .convert(await File('docs/ep-001/historico-ejemplo.csv').readAsBytes())
        .toString();
    if (!{'windows', 'android'}.contains(platform) ||
        data?['syntheticDataOnly'] != true ||
        data?['csvSha256'] != csvHash ||
        stages == null ||
        stages.length != requiredStages.length ||
        !stages.keys.toSet().containsAll(requiredStages)) {
      throw StateError(
        'Evidencia nativa incompleta o CSV ajeno al contrato EP-001.',
      );
    }
    final directory = await Directory('docs/ep-025/recorrido-nativo')
        .create(recursive: true);
    await File('${directory.path}/$platform.json')
        .writeAsString('${const JsonEncoder.withIndent('  ').convert(data)}\n');
  },
);
