import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../test/support/category_lifecycle_journey.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Gestión completa e integridad histórica en SQLite nativo', (
    tester,
  ) async {
    // En profile el cliente -1 de enterText no se acepta. Registrar la entrada
    // de prueba proporciona un cliente válido sin depender del IME del host.
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final support = await getApplicationSupportDirectory();
    final fixtures = await Directory(p.join(support.path, 'category-ui-tests'))
        .create(recursive: true);
    // El host empaquetado puede redirigir Roaming. Usar la ubicación física
    // de la carpeta sintética, conservando las comprobaciones de rutas reales.
    final temporary = await fixtures.createTemp('synthetic-085-');
    final directory = Directory(await temporary.resolveSymbolicLinks());
    try {
      await categoryLifecycleJourney(tester, directory);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
