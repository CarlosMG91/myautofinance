import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../test/support/report_drilldown_journey.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  testWidgets('MA-TSK-194 tres informes y desgloses nativos', (tester) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final support = await getApplicationSupportDirectory();
    final fixtures = await Directory(p.join(support.path, 'drilldown-tests'))
        .create(recursive: true);
    final root = await fixtures.resolveSymbolicLinks();
    final temporary = await fixtures.createTemp(
      'synthetic-drilldowns-194-native-',
    );
    // El restaurador exige rutas canónicas; Android expone alias internos.
    final directory = Directory(await temporary.resolveSymbolicLinks());
    if (!p.isWithin(root, directory.path)) {
      throw StateError('La instalación sintética queda fuera de las pruebas.');
    }
    try {
      await binding.setSurfaceSize(
        Platform.isWindows ? const Size(1440, 1000) : const Size(412, 1000),
      );
      await reportDrilldownJourney(tester, directory);
    } finally {
      await binding.setSurfaceSize(null);
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
