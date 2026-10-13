import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/features/movements/movement_widgets.dart';
import 'package:myautofinance/features/movements/presentation/movement_list_screen.dart';
import 'package:myautofinance/features/movements/presentation/pending_movement_screen.dart';
import 'package:myautofinance/app/navigation/primary_navigation.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';

import '../../examples/movements_review.dart';

Future<void> settle(WidgetTester tester) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
    final lists = find.byType(MovementListScreen);
    final pending = find.byType(PendingMovementScreen);
    if ((lists.evaluate().isEmpty ||
            !tester.widget<MovementListScreen>(lists).controller.loading) &&
        (pending.evaluate().isEmpty ||
            !tester
                .widget<PendingMovementScreen>(pending)
                .controller
                .loading) &&
        find.text('Cargando detalle…').evaluate().isEmpty) {
      return;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('AfRoboto');
    for (final weight in ['regular', 'medium', 'bold']) {
      loader.addFont(rootBundle.load('assets/fonts/roboto-$weight.ttf'));
    }
    await loader.load();
  });
  for (final (width, scale) in [(1440.0, 1.0), (360.0, 1.0), (320.0, 2.0)]) {
    testWidgets(
      'Actividad y bandeja: retorno, neto cero y duplicados $width/$scale',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final data = (await tester.runAsync(createMovementReviewData))!;
        addTearDown(data.close);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(key: boundary, child: data.app()),
        );
        await settle(tester);
        final c = tester
            .widget<MovementListScreen>(find.byType(MovementListScreen))
            .controller;
        expect(c.page!.totalCount, 4);
        expect(c.page!.subtotalCents, 0);
        expect(find.byType(MovementActivityRow), findsNWidgets(4));
        expect(find.text('Café'), findsNWidgets(2));
        await tester.ensureVisible(find.text('Abrir Café').first);
        await tester.pumpAndSettle();
        final scroll = tester
            .widget<SingleChildScrollView>(
              find
                  .byWidgetPredicate(
                    (widget) =>
                        widget is SingleChildScrollView &&
                        widget.controller != null,
                  )
                  .last,
            )
            .controller!;
        final offset = scroll.offset;
        c.selectPage();
        await tester.pumpAndSettle();
        await capture(
          tester,
          boundary,
          'actividad-${width.toInt()}-${scale.toInt()}',
        );
        if (width >= 840) {
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Abrir Café').first,
              )
              .focusNode!
              .requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        } else {
          await tester.tap(find.text('Abrir Café').first);
        }
        await settle(tester);
        expect(
          find.text('Discrecionalidad: Texto sintético conservado'),
          findsOneWidget,
        );
        expect(find.textContaining('Procedencia:'), findsOneWidget);
        final detailSession = tester
            .widget<PrimaryNavigation>(find.byType(PrimaryNavigation))
            .session;
        expect(detailSession, isNot(same(data.session)));
        await detailSession.selectPeriod(NavigationPeriod(2026, 4));
        await tester.pumpAndSettle();
        expect(data.session.period.month, 3);
        await tester.ensureVisible(find.text('Volver a Movimientos'));
        await tester.tap(find.text('Volver a Movimientos'));
        await settle(tester);
        expect(c.selected, hasLength(4));
        expect(scroll.offset, closeTo(offset, 0.1));
        await tester.ensureVisible(find.text('Categorizar pendientes').first);
        await tester.tap(find.text('Categorizar pendientes').first);
        await settle(tester);
        expect(find.byType(PendingMovementScreen), findsOneWidget);
        final pending = tester
            .widget<PendingMovementScreen>(find.byType(PendingMovementScreen))
            .controller;
        expect(pending.page!.totalCount, 3);
        expect(pending.page!.subtotalCents, 6534);
        final pendingSession = tester
            .widget<PrimaryNavigation>(find.byType(PrimaryNavigation))
            .session;
        await pendingSession.selectPeriod(NavigationPeriod(2026, 5));
        await tester.pumpAndSettle();
        expect(data.session.period.month, 3);
        await tester.ensureVisible(find.text('Categorizar Café').first);
        await tester.pumpAndSettle();
        await capture(
          tester,
          boundary,
          'pendientes-${width.toInt()}-${scale.toInt()}',
        );
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await settle(tester);
        expect(c.from.value, '2026-03-01');
        expect(c.selected, hasLength(4));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['MOVEMENT_REDESIGN_CAPTURE'] != '1') return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final picture = await boundary.toImage();
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('docs/ep-026/movimientos-capturas');
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}
