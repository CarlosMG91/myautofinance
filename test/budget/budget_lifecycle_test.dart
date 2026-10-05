import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/budget_lifecycle_journey.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets('EP-011 recorrido SQLite de archivo: ${platform.name}', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(
        platform == TargetPlatform.windows ? 1440 : 412,
        1000,
      );
      final directory = (await tester.runAsync(() async {
        final temporary = await Directory.systemTemp.createTemp(
          'budget-105-synthetic-',
        );
        return Directory(await temporary.resolveSymbolicLinks());
      }))!;
      try {
        await budgetLifecycleJourney(
          tester,
          directory,
          desktop: platform == TargetPlatform.windows,
        );
      } finally {
        await tester.runAsync(() => directory.delete(recursive: true));
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        debugDefaultTargetPlatformOverride = null;
      }
    }, timeout: const Timeout(Duration(minutes: 6)));
  }
}
