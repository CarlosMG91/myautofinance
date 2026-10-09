import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/historical_navigation_journey.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets('Histórico integrado con SQLite en archivo: ${platform.name}', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(
        platform == TargetPlatform.windows ? 1440 : 412,
        1000,
      );
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('synthetic-146-'),
      ))!;
      try {
        await historicalNavigationJourney(tester, directory);
      } finally {
        await tester.runAsync(() => directory.delete(recursive: true));
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
        debugDefaultTargetPlatformOverride = null;
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
