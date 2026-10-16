import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

const captureDrilldowns = bool.fromEnvironment('CAPTURE_DRILLDOWNS');
final drilldownCaptureKey = GlobalKey();

Future<void> loadDrilldownFonts() async {
  if (!captureDrilldowns) return;
  final loader = FontLoader(AfTokens.family);
  for (final weight in ['regular', 'medium', 'bold']) {
    loader.addFont(rootBundle.load('assets/fonts/roboto-$weight.ttf'));
  }
  await loader.load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}

Future<void> captureDrilldown(
  WidgetTester tester,
  String name, {
  GlobalKey? key,
}) async {
  if (!captureDrilldowns) return;
  final boundary =
      (key ?? drilldownCaptureKey).currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
  final bitmap = (await tester.runAsync(
    () => boundary.toImage(pixelRatio: 1),
  ))!;
  final bytes = (await tester.runAsync(
    () => bitmap.toByteData(format: ui.ImageByteFormat.png),
  ))!;
  await tester.runAsync(() async {
    await Directory('.tools/tsk192-renders').create(recursive: true);
    await File('.tools/tsk192-renders/$name.png')
        .writeAsBytes(bytes.buffer.asUint8List());
  });
  bitmap.dispose();
}
