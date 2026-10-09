import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../test/support/pending_lifecycle_journey.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('EP-015 categorización y procedencia con SQLite nativo', (
    tester,
  ) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final support = await getApplicationSupportDirectory();
    final fixtures = await Directory(
      p.join(support.path, 'pending-categorization-tests'),
    ).create(recursive: true);
    final temporary = await fixtures.createTemp('synthetic-138-');
    final directory = Directory(await temporary.resolveSymbolicLinks());
    try {
      await pendingLifecycleJourney(
        tester,
        directory,
        desktop: Platform.isWindows,
      );
    } finally {
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
