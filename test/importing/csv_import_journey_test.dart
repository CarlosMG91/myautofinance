import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/csv_import_journey.dart';
import '../support/csv_test_bundle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Bundle nativo conserva exactamente los archivos originales del checkout',
    () async {
      for (final entry in csvTestBundle.entries) {
        final path = entry.key == 'historico-ejemplo.csv'
            ? 'docs/ep-001/${entry.key}'
            : 'docs/ep-013/fixtures/archivos/${entry.key}';
        expect(
          base64Decode(entry.value),
          await File(path).readAsBytes(),
          reason: entry.key,
        );
      }
    },
  );
  for (final entry in csvJourneyCases.entries) {
    test('EP-013 ${entry.key}', () async {
      final directory = await Directory.systemTemp.createTemp(
        'synthetic-csv-122-',
      );
      final journey = CsvImportJourney(directory);
      try {
        await journey.open();
        await entry.value(journey);
      } finally {
        await journey.close();
        await directory.delete(recursive: true);
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
