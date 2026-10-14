import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../test/support/redesign_journey.dart';
import 'budget_proposal_acceptance_test.dart' as proposal;
import 'import_redesign_test.dart' as importing;
import 'pending_categorization_test.dart' as pending;
import 'synchronization_redesign_test.dart' as copies;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  // Reutilizar recorridos financieros de sus propietarios, sin otro motor.
  importing.main();
  pending.main();
  proposal.main();
  copies.main();
  final captures = <String, String>{};
  final results = <Map<String, Object>>[];
  final scenarios = Platform.isWindows
      ? [(1440.0, 900.0, 1.0), (1024.0, 768.0, 1.0), (320.0, 800.0, 2.0)]
      : [(412.0, 915.0, 1.0), (360.0, 800.0, 1.0), (320.0, 800.0, 2.0)];
  for (final (width, height, scale) in scenarios) {
    testWidgets(
      'MA-TSK-217 nativo $width/$scale: recorrido global SQLite sintético',
      (tester) async {
        binding.reportData = {
          ...?binding.reportData,
          'redesignCaptures': captures,
          'results': results,
          'runtime': {
            'platform': Platform.operatingSystem,
            'dart': Platform.version.split(' ').first,
            'capturedAtUtc': DateTime.now().toUtc().toIso8601String(),
            'origin': 'Native Flutter RenderRepaintBoundary',
            'surfaceSizeForced': true,
            'textScaleForced': true,
            'syntheticDataOnly': true,
          },
        };
        tester.testTextInput.register();
        addTearDown(tester.testTextInput.unregister);
        final support = await getApplicationSupportDirectory();
        final root = await Directory(p.join(support.path, 'redesign-217-tests'))
            .create(recursive: true);
        final temporary = await root.createTemp('synthetic-');
        // Android presenta aliases /data/user/0 y /data/data para su carpeta
        // privada. El coordinador real de recuperación exige ruta canónica.
        final directory = Directory(await temporary.resolveSymbolicLinks());
        if (!p.isWithin(await root.resolveSymbolicLinks(), directory.path)) {
          throw StateError(
            'La instalación sintética queda fuera de su ámbito.',
          );
        }
        final boundary = GlobalKey();
        try {
          results.add(
            await redesignJourney(
              tester,
              directory,
              size: Size(width, height),
              scale: scale,
              captureKey: boundary,
              largeDataset: width == scenarios.first.$1,
              capture: (name) async {
                final render =
                    boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final picture = await render.toImage();
                final bytes = (await picture.toByteData(
                  format: ui.ImageByteFormat.png,
                ))!.buffer.asUint8List();
                picture.dispose();
                final file =
                    '${Platform.operatingSystem}-${width.toInt()}-${scale.toInt()}-$name.png';
                captures[file] = base64Encode(bytes);
              },
            ),
          );
        } finally {
          await directory.delete(recursive: true);
        }
      },
      timeout: const Timeout(Duration(minutes: 8)),
    );
  }
}
