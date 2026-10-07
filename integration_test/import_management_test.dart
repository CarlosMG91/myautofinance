import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../test/support/import_lifecycle_journey.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('EP-012 importación con adaptador sintético y SQLite nativo', (
    tester,
  ) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final support = await getApplicationSupportDirectory();
    final fixtures = await Directory(p.join(support.path, 'import-ui-tests'))
        .create(recursive: true);
    final temporary = await fixtures.createTemp('synthetic-114-');
    final directory = Directory(await temporary.resolveSymbolicLinks());
    try {
      await importLifecycleJourney(
        tester,
        directory,
        desktop: Platform.isWindows,
      );
    } finally {
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
