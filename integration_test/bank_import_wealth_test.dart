import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../test/support/bank_import_wealth_journey.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'EP-012 bankXls y fotos pobladas sobre SQLite nativo; sin lector Openbank',
    (tester) async {
      final support = await getApplicationSupportDirectory();
      final fixtures = await Directory(
        p.join(support.path, 'bank-wealth-tests'),
      ).create(recursive: true);
      final temporary = await fixtures.createTemp('synthetic-131-');
      // El almacenamiento Android puede devolver una ruta con enlaces internos.
      // Usar la raíz canónica, como los otros recorridos nativos de SQLite.
      final directory = Directory(await temporary.resolveSymbolicLinks());
      try {
        await bankImportWealthJourney(directory);
      } finally {
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
