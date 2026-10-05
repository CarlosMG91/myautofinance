import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/movement_lifecycle_journey.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets('Recorrido EP-010 en SQLite en archivo: ${platform.name}', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(
        platform == TargetPlatform.windows ? 1440 : 412,
        1000,
      );
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('movement-095-synthetic-'),
      ))!;
      try {
        await movementLifecycleJourney(tester, directory);
      } finally {
        await tester.runAsync(() => directory.delete(recursive: true));
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        debugDefaultTargetPlatformOverride = null;
      }
    }, timeout: const Timeout(Duration(minutes: 6)));
  }
}
