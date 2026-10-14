import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import '../test/support/annual_actual_lifecycle_journey.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  testWidgets('MA-TSK-180 Real anual y origen nativos', (tester) async {
    final root = await getTemporaryDirectory();
    final directory = await root.createTemp('synthetic-180-native-');
    try {
      await binding.setSurfaceSize(
        Platform.isWindows ? const Size(1440, 1000) : const Size(412, 1000),
      );
      await annualActualLifecycleJourney(
        tester,
        directory,
        desktop: Platform.isWindows,
      );
    } finally {
      await binding.setSurfaceSize(null);
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
