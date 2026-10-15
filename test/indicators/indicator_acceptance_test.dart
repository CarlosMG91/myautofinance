import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/indicator_acceptance.dart';

void main() {
  for (final desktop in [true, false]) {
    testWidgets(
      'MA-TSK-188 aceptación SQLite ${desktop ? 'Windows' : 'Android'}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(desktop ? 1440 : 412, 1000);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await indicatorAcceptance(tester);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
