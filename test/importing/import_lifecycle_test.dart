import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/import_lifecycle_journey.dart';

void main() {
  for (final desktop in [true, false]) {
    testWidgets('EP-012 recorrido completo ${desktop ? 'tabla' : 'tarjetas'}', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = desktop
          ? TargetPlatform.windows
          : TargetPlatform.android;
      tester.view.physicalSize = Size(desktop ? 1280 : 390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = (await tester.runAsync(() async {
        final temporary = await Directory.systemTemp.createTemp(
          'synthetic-import-114-',
        );
        return Directory(await temporary.resolveSymbolicLinks());
      }))!;
      try {
        await importLifecycleJourney(tester, directory, desktop: desktop);
      } finally {
        await tester.runAsync(() => directory.delete(recursive: true));
        debugDefaultTargetPlatformOverride = null;
      }
    }, timeout: const Timeout(Duration(minutes: 6)));
  }
}
