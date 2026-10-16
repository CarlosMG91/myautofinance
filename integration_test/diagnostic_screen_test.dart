import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

import '../test/support/diagnostic_journey.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  final captures = <String, String>{};
  final boundary = GlobalKey();
  binding.reportData = {
    'diagnosticCaptures': captures,
    'runtime': {
      'platform': Platform.operatingSystem,
      'syntheticDataOnly': true,
      'origin': 'Native Flutter RenderRepaintBoundary',
      'surfaceSizeForced': true,
      'capturedAtUtc': DateTime.now().toUtc().toIso8601String(),
    },
  };
  testWidgets('MA-TSK-201 diagnóstico manual SQLite y navegación nativa', (
    tester,
  ) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final support = await getApplicationSupportDirectory();
    final root = await Directory('${support.path}/synthetic-diagnostic-tests')
        .create(recursive: true);
    final temp = await root.createTemp('run-');
    final directory = Directory(await temp.resolveSymbolicLinks());
    try {
      await binding.setSurfaceSize(
        Platform.isWindows ? const Size(1440, 1100) : const Size(412, 1100),
      );
      await diagnosticJourney(
        tester,
        directory,
        captureKey: boundary,
        capture: (name) async {
          final scroll = tester
              .widget<AfShell>(find.byType(AfShell))
              .scrollController!;
          final offset = scroll.offset;
          if (name == 'detalle' || name == 'foto-pendiente') {
            await tester.ensureVisible(find.byType(ExpansionTile).first);
          } else {
            scroll.jumpTo(0);
          }
          await tester.pumpAndSettle();
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final picture = await render.toImage();
          final bytes = (await picture.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List();
          picture.dispose();
          captures['${Platform.operatingSystem}-$name.png'] = base64Encode(
            bytes,
          );
          scroll.jumpTo(offset);
          await tester.pumpAndSettle();
        },
      );
    } finally {
      await binding.setSurfaceSize(null);
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
