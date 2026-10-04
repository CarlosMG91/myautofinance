import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/category_lifecycle_journey.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets('Ciclo completo con SQLite en archivo: ${platform.name}', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(
        platform == TargetPlatform.windows ? 1440 : 412,
        900,
      );
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('category-lifecycle-synthetic-'),
      ))!;
      try {
        await categoryLifecycleJourney(tester, directory);
      } finally {
        await tester.runAsync(() => directory.delete(recursive: true));
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
