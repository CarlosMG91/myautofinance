import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../test/support/historical_navigation_journey.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('MA-TSK-146 navegación histórica con SQLite nativo', (
    tester,
  ) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final support = await getApplicationSupportDirectory();
    final fixtures = await Directory(
      p.join(support.path, 'historical-navigation-tests'),
    ).create(recursive: true);
    final directory = await fixtures.createTemp('synthetic-146-');
    try {
      await historicalNavigationJourney(tester, directory);
    } finally {
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
