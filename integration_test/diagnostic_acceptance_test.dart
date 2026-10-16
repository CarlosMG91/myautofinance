import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import '../test/support/diagnostic_acceptance_journey.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  final stages = <String, Object?>{};
  // Comprimir evita superar el límite de cmd.exe al compilar en Windows.
  final csv = gzip.decode(
    base64Decode(const String.fromEnvironment('SYNTHETIC_CSV_GZIP_BASE64')),
  );
  binding.reportData = {
    'ticket': 'MA-TSK-202',
    'platform': Platform.operatingSystem,
    'syntheticDataOnly': true,
    'origin': 'Native Flutter integration_test; production SQLite services',
    'surfaceSizeForced': true,
    'androidBack': 'Flutter binding handlePopRoute',
    'csvSha256': sha256.convert(csv).toString(),
    'startedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'stages': stages,
  };
  testWidgets('MA-TSK-202 recorrido completo nativo con CSV EP-001', (
    tester,
  ) async {
    expect(
      csv,
      isNotEmpty,
      reason: 'Inyectar únicamente el CSV sintético aprobado',
    );
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final support = await getApplicationSupportDirectory();
    final root = await Directory(
      '${support.path}/synthetic-diagnostic-acceptance',
    ).create(recursive: true);
    final temporary = await root.createTemp('run-');
    final directory = Directory(await temporary.resolveSymbolicLinks());
    try {
      await binding.setSurfaceSize(
        Platform.isWindows ? const Size(1440, 1100) : const Size(412, 1100),
      );
      await diagnosticAcceptanceJourney(
        tester,
        directory,
        csv,
        evidence: (stage, data) async {
          stages[stage] = data;
        },
      );
    } finally {
      await binding.setSurfaceSize(null);
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 7)));
}
