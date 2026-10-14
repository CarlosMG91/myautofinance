import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/redesign_journey.dart';
import 'ui/kit_test.dart' show loadAfFonts;

void main() {
  setUpAll(loadAfFonts);
  for (final (width, height, scale) in [
    (1440.0, 900.0, 1.0),
    (1024.0, 768.0, 1.0),
    (412.0, 915.0, 1.0),
    (360.0, 800.0, 1.0),
    (320.0, 800.0, 2.0),
  ]) {
    testWidgets(
      'Rediseño integrado $width/$scale: Inicio, edición, retorno y rutas',
      (tester) async {
        final directory = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('synthetic-redesign-217-'),
        ))!;
        try {
          final metrics = await redesignJourney(
            tester,
            directory,
            size: Size(width, height),
            scale: scale,
            captureKey: GlobalKey(),
            largeDataset: width == 1440,
          );
          expect(metrics['reopened'], isTrue);
        } finally {
          await tester.runAsync(() => directory.delete(recursive: true));
        }
      },
    );
  }
}
