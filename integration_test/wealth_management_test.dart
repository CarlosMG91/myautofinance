import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../test/support/wealth_lifecycle_journey.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Caso D y recorrido completo de patrimonio en SQLite nativo', (
    tester,
  ) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final support = await getApplicationSupportDirectory();
    final fixtures = await Directory(p.join(support.path, 'wealth-ui-tests'))
        .create(recursive: true);
    final temporary = await fixtures.createTemp('synthetic-077-');
    final directory = Directory(await temporary.resolveSymbolicLinks());
    try {
      await wealthLifecycleJourney(
        tester,
        directory,
        captures: Directory(
          p.join(
            await fixtures.resolveSymbolicLinks(),
            'captures-${Platform.operatingSystem}',
          ),
        ),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
