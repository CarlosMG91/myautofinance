import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../test/support/annual_budget_lifecycle_journey.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('EP-021 matriz anual y persistencia SQLite nativa', (
    tester,
  ) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final support = await getApplicationSupportDirectory();
    final fixtures = await Directory(
      p.join(support.path, 'annual-budget-tests'),
    ).create(recursive: true);
    final root = await fixtures.resolveSymbolicLinks();
    final temporary = await fixtures.createTemp('synthetic-172-');
    final directory = Directory(await temporary.resolveSymbolicLinks());
    if (!p.isWithin(root, directory.path)) {
      throw StateError(
        'La carpeta sintética queda fuera del ámbito de pruebas.',
      );
    }
    try {
      await annualBudgetLifecycleJourney(
        tester,
        directory,
        desktop: Platform.isWindows,
      );
    } finally {
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
