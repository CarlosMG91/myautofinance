import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/bank_import_wealth_journey.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'EP-012 bankXls sintético protege fotos pobladas; no lee Openbank',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bank-wealth-131-',
      );
      try {
        await bankImportWealthJourney(directory);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
