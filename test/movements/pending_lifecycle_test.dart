import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pending_lifecycle_journey.dart';

void main() {
  for (final desktop in [true, false]) {
    testWidgets(
      'EP-015 completo con SQLite: ${desktop ? 'Windows tabla' : 'Android tarjetas'}',
      (tester) async {
        debugDefaultTargetPlatformOverride = desktop
            ? TargetPlatform.windows
            : TargetPlatform.android;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(desktop ? 1440 : 412, 1000);
        final directory = (await tester.runAsync(() async {
          final temporary = await Directory.systemTemp.createTemp(
            'pending-138-journey-',
          );
          return Directory(await temporary.resolveSymbolicLinks());
        }))!;
        try {
          await pendingLifecycleJourney(tester, directory, desktop: desktop);
        } finally {
          await tester.runAsync(() => directory.delete(recursive: true));
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          debugDefaultTargetPlatformOverride = null;
        }
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );
  }
}
