import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/report_drilldown_journey.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets('MA-TSK-194 tres informes SQLite: ${platform.name}', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(
        platform == TargetPlatform.windows ? 1440 : 412,
        1000,
      );
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('synthetic-drilldowns-194-'),
      ))!;
      try {
        await reportDrilldownJourney(tester, directory);
      } finally {
        await tester.runAsync(() => directory.delete(recursive: true));
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
        debugDefaultTargetPlatformOverride = null;
      }
    }, timeout: const Timeout(Duration(minutes: 8)));
  }
}
