import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/wealth_lifecycle_journey.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets('Caso D completo en archivo SQLite: ${platform.name}', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(
        platform == TargetPlatform.windows ? 1440 : 412,
        900,
      );
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('wealth-synthetic-077-'),
      ))!;
      final capturing = Platform.environment.containsKey(
        'CAPTURE_WEALTH_JOURNEY',
      );
      try {
        if (capturing) {
          await tester.runAsync(() async {
            final font = FontLoader(
              platform == TargetPlatform.windows ? 'Segoe UI' : 'Roboto',
            );
            font.addFont(
              Future.value(
                ByteData.sublistView(
                  await File('C:/Windows/Fonts/segoeui.ttf').readAsBytes(),
                ),
              ),
            );
            await font.load();
          });
        }
        await wealthLifecycleJourney(
          tester,
          directory,
          captures: capturing
              ? Directory('.tools/077-${platform.name}-widgets')
              : null,
        );
      } finally {
        await tester.runAsync(() => directory.delete(recursive: true));
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        debugDefaultTargetPlatformOverride = null;
      }
    }, timeout: const Timeout(Duration(minutes: 4)));
  }
}
