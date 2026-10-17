import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/features/synchronization/export_saving.dart';
import 'package:myautofinance/features/synchronization/presentation/export_controller.dart';
import 'package:myautofinance/features/synchronization/presentation/export_screen.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

import '../support/app_navigation.dart';
import 'export_support.dart';

Future<void> tapText(WidgetTester tester, String label) async {
  await tester.pump();
  final finder = find.text(label).last;
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  Future<void> screen(
    WidgetTester tester,
    ExportController controller, {
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AfTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: ExportScreen(controller: controller, onReturn: () {}),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Gestión abre ambos modos, guía y retorno conservando el periodo',
    (tester) async {
      final f = ExportFixture();
      final session = NavigationSession(clock: () => DateTime.utc(2026, 4, 6));
      addTearDown(session.dispose);
      await tester.pumpWidget(
        AutofinanceApp(exports: f.controller, navigationSession: session),
      );
      await selectAppDestination(tester, SessionDestination.management);
      for (final mode in ['Exportar datos', 'Exportar copia completa']) {
        await tapText(tester, mode);
        expect(find.byType(ExportScreen), findsOneWidget);
        await tapText(tester, 'Consultar guía');
        expect(find.text('Leer tus datos sin Autofinance'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('Resumen del contenido'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(ExportScreen), findsNothing);
        expect(session.period, NavigationPeriod(2026, 4));
      }
      expect(f.filters, isEmpty);
    },
  );

  testWidgets(
    'Mes inválido, selección conservada, cancelación nativa y nueva captura',
    (tester) async {
      final f = ExportFixture()..outcome = const ExportSaveCancelled();
      final c = f.controller();
      await screen(tester, c);
      await tapText(tester, 'Rango de meses');
      await tester.enterText(
        find.byKey(const ValueKey('export-from')),
        '2026-03',
      );
      await tester.enterText(
        find.byKey(const ValueKey('export-through')),
        '2026-01',
      );
      await tapText(tester, 'Guardar ZIP');
      expect(f.filters, isEmpty);
      expect(find.textContaining('Elige ambos meses'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('export-through')),
        '2026-03',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tapText(tester, 'Guardar ZIP');
      expect(c.message, contains('cancelado el selector'));
      expect(c.from, '2026-03');
      expect(c.through, '2026-03');
      f.outcome = const ExportSaved(
        location: 'content://synthetic/document/1',
        displayName: 'elegido.zip',
      );
      await tapText(tester, 'Reintentar guardado');
      expect(f.requests, hasLength(2));
      expect(find.text('Nombre guardado: elegido.zip'), findsOneWidget);
      expect(find.textContaining('Revisión capturada: 2'), findsOneWidget);
      expect(find.textContaining('Contenido verificado:'), findsOneWidget);
    },
  );

  testWidgets(
    'Back durante escritura espera el resultado real sin éxito anticipado',
    (tester) async {
      final f = ExportFixture()..saving = Completer<ExportSaveResult>();
      final c = f.controller();
      await screen(tester, c);
      await tapText(tester, 'Guardar ZIP');
      expect(c.phase, ExportPhase.saving);
      expect(find.textContaining('ZIP guardado.'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('¿Salir durante el guardado?'), findsOneWidget);
      await tapText(tester, 'Solicitar salir y esperar');
      expect(find.byType(ExportScreen), findsOneWidget);
      expect(f.prepared.single.disposals, 0);
      expect(f.requests, hasLength(1));
      f.saving!.complete(const ExportSaved());
      await tester.pumpAndSettle();
      expect(find.textContaining('ZIP guardado.'), findsOneWidget);
      expect(find.textContaining('Ubicación no facilitada'), findsOneWidget);
      expect(f.prepared.single.disposals, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Back de borrador ofrece continuar o descartar; Escape mantiene selección',
    (tester) async {
      final f = ExportFixture();
      final c = f.controller();
      await screen(tester, c);
      await tapText(tester, 'Rango de meses');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('¿Descartar el borrador?'), findsOneWidget);
      await tapText(tester, 'Continuar');
      expect(c.months, isTrue);
      expect(f.filters, isEmpty);
    },
  );

  for (final mode in ExportMode.values) {
    testWidgets(
      '320 px y texto 200 %, ${mode.name}: formulario, resultado y guía accesibles',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          final f = ExportFixture();
          final c = f.controller()..mode = mode;
          await screen(tester, c, scale: 2);
          expect(tester.takeException(), isNull);
          await tapText(tester, 'Guardar ZIP');
          await tester.pumpAndSettle();
          expect(c.result, isA<ExportSaved>());
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await tapText(tester, 'Consultar guía');
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tapText(tester, 'Volver al recorrido');
          expect(find.text('Resumen del contenido'), findsOneWidget);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
