import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/diagnostic_journey.dart';

void main() {
  for (final width in [1440.0, 412.0]) {
    testWidgets('diagnóstico SQLite, bandeja, restauración y foto $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('synthetic-diagnostic-'),
      ))!;
      try {
        await diagnosticJourney(tester, directory);
      } finally {
        await tester.runAsync(() => directory.delete(recursive: true));
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
