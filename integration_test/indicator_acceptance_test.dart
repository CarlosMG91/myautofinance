import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import '../test/support/indicator_acceptance.dart';
import '../test/support/indicator_journey.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  final completed = <String>[];
  binding.reportData = {
    'ticket': 'MA-TSK-188',
    'platform': Platform.operatingSystem,
    'dart': Platform.version.split(' ').first,
    'appEnvironment': const String.fromEnvironment('APP_ENV'),
    'syntheticDataOnly': true,
    'startedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'completed': completed,
  };

  testWidgets('MA-TSK-188 contrato integrado SQLite nativo', (tester) async {
    await binding.setSurfaceSize(Size(Platform.isWindows ? 1440 : 412, 1000));
    try {
      await indicatorAcceptance(tester);
      completed.add('sqlite-contract-and-extension');
    } finally {
      await binding.setSurfaceSize(null);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('MA-TSK-188 ciclo completo y retorno a ambos orígenes', (
    tester,
  ) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final support = await getApplicationSupportDirectory();
    final root = await Directory(
      '${support.path}/synthetic-indicator-acceptance',
    ).create(recursive: true);
    final temporary = await root.createTemp('run-');
    final directory = Directory(await temporary.resolveSymbolicLinks());
    await binding.setSurfaceSize(Size(Platform.isWindows ? 1440 : 412, 1000));
    try {
      await indicatorJourney(tester, directory, desktop: Platform.isWindows);
      completed.add('source-return-import-restore-reopen');
    } finally {
      await binding.setSurfaceSize(null);
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
