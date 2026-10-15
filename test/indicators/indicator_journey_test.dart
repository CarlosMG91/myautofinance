import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/indicator_journey.dart';

void main() {
  for (final desktop in [true, false]) {
    testWidgets(
      'Indicadores SQLite y retorno ${desktop ? 'Windows' : 'Android'}',
      (tester) async {
        debugDefaultTargetPlatformOverride = desktop
            ? TargetPlatform.windows
            : TargetPlatform.android;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(desktop ? 1440 : 412, 1000);
        final directory = (await tester.runAsync(() async {
          final temp = await Directory.systemTemp.createTemp(
            'synthetic-indicator-',
          );
          return Directory(await temp.resolveSymbolicLinks());
        }))!;
        try {
          await indicatorJourney(tester, directory, desktop: desktop);
        } finally {
          debugDefaultTargetPlatformOverride = null;
          await tester.runAsync(() => directory.delete(recursive: true));
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        }
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );
  }
}
