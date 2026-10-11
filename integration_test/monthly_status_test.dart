import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../test/support/monthly_status_journey.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  testWidgets('MA-TSK-164 Estado, fuentes y restauración con SQLite nativo', (
    tester,
  ) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final support = await getApplicationSupportDirectory();
    final fixtures = await Directory(
      p.join(support.path, 'monthly-status-tests'),
    ).create(recursive: true);
    final root = await fixtures.resolveSymbolicLinks();
    final temporary = await fixtures.createTemp('synthetic-164-');
    // Android puede devolver rutas con enlaces internos; el restaurador
    // valida rutas canónicas antes de reemplazar una base.
    final directory = Directory(await temporary.resolveSymbolicLinks());
    if (!p.isWithin(root, directory.path)) {
      throw StateError(
        'La carpeta sintética queda fuera del ámbito de pruebas.',
      );
    }
    try {
      await monthlyStatusJourney(tester, directory);
    } finally {
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 12)));
}
