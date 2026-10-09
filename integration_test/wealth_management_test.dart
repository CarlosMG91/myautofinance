import 'dart:io';

import 'package:flutter/foundation.dart';
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
        androidBack:
            Platform.isAndroid &&
                const bool.fromEnvironment('WEALTH_ANDROID_BACK')
            ? () async {
                debugPrint(
                  'MA-TSK-148: esperando KEYCODE_BACK '
                  '${const String.fromEnvironment('WEALTH_ANDROID_BACK_RUN')}',
                );
                for (var turn = 0; turn < 300; turn++) {
                  await tester.runAsync(
                    () =>
                        Future<void>.delayed(const Duration(milliseconds: 100)),
                  );
                  await tester.pump();
                  if (find
                      .text('Hay cambios sin guardar')
                      .evaluate()
                      .isNotEmpty) {
                    return;
                  }
                }
                fail(
                  'El host no envió Android Back o no protegió el borrador.',
                );
              }
            : null,
      );
    } finally {
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 12)));
}
