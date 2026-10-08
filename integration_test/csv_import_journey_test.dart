import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import '../test/support/csv_import_journey.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final entry in csvJourneyCases.entries) {
    testWidgets('EP-013 CSV nativo: ${entry.key}', (tester) async {
      await tester.runAsync(() async {
        final support = await getApplicationSupportDirectory();
        final fixtures = await Directory('${support.path}/csv-import-tests')
            .create(recursive: true);
        final temporary = await fixtures.createTemp('synthetic-122-');
        final directory = Directory(await temporary.resolveSymbolicLinks());
        final journey = CsvImportJourney(directory);
        try {
          await journey.open();
          await entry.value(journey);
        } finally {
          await journey.close();
          await directory.delete(recursive: true);
        }
      });
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
