import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/diagnostic_acceptance_journey.dart';

void main() {
  for (final width in [1440.0, 412.0]) {
    testWidgets(
      'MA-TSK-202 importar, diagnosticar, corregir y repetir $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final directory = (await tester.runAsync(
          () => Directory.systemTemp.createTemp(
            'synthetic-diagnostic-acceptance-',
          ),
        ))!;
        try {
          await diagnosticAcceptanceJourney(
            tester,
            directory,
            File('docs/ep-001/historico-ejemplo.csv').readAsBytesSync(),
          );
        } finally {
          await tester.runAsync(() => directory.delete(recursive: true));
        }
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}
