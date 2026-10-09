import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/features/movements/presentation/movement_list_controller.dart';
import 'package:myautofinance/features/movements/presentation/movement_list_screen.dart';

import 'historical_navigation_fixture.dart';

/// Mismo guion en widgets de PC/móvil y en el runner nativo de ambas plataformas.
Future<void> historicalNavigationJourney(
  WidgetTester tester,
  Directory directory,
) async {
  final data = HistoricalNavigationFixture(
    file: File('${directory.path}/historical-navigation.sqlite'),
  );
  var now = DateTime.utc(2025, 12, 31, 23, 30);
  final session = NavigationSession(clock: () => now);
  Future<T> io<T>(Future<T> Function() operation) async =>
      (await tester.runAsync(operation)) as T;

  Future<void> settle() async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump(const Duration(milliseconds: 50));
      if (i >= 5 &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        return;
      }
    }
    fail('La consulta histórica no terminó.');
  }

  Future<void> tap(Finder target) async {
    await tester.ensureVisible(target);
    await tester.runAsync(() => tester.tap(target));
    await settle();
  }

  Future<void> press(String text) => tap(find.text(text).last);
  Future<void> year(String value) async {
    await tester.enterText(find.byKey(const Key('period-year')), value);
    await press('Ir al periodo');
  }

  Future<void> destination(String label) =>
      tap(find.widgetWithText(TextButton, label).last);
  NavigatorState nav() => tester.state(find.byType(Navigator).first);
  MovementListController list() => tester
      .widget<MovementListScreen>(find.byType(MovementListScreen))
      .controller;

  try {
    await io(data.seed);
    final before = await io(data.database.readState);
    await tester.pumpWidget(
      AutofinanceApp(
        navigationSession: session,
        categories: () async => data.categories,
        wealth: () async => data.wealth,
        budgets: () async => data.budget,
        movements: () async => data.movements,
      ),
    );
    await settle();
    expect(session.period, NavigationPeriod(2026, 1));
    expect(find.text('Periodo de consulta: 2026-01'), findsOneWidget);

    await destination('Patrimonio');
    expect(find.text('Sin dato: foto patrimonial incompleta'), findsOneWidget);
    expect(find.text('Pendientes: Deuda sintética'), findsOneWidget);
    await press('Mes anterior');
    expect(session.period, NavigationPeriod(2025, 12));
    expect(find.text('Patrimonio neto: 800,00\u00a0€'), findsOneWidget);
    await press('Mes siguiente');
    expect(session.period, NavigationPeriod(2026, 1));
    await press('Mes siguiente');
    expect(find.text('Patrimonio neto: 0,00\u00a0€'), findsOneWidget);
    await press('Mes siguiente');
    expect(find.text('Sin dato: falta foto patrimonial'), findsOneWidget);
    expect(find.text('Patrimonio neto: Sin dato'), findsOneWidget);

    await destination('Presupuesto');
    expect(session.context.view, PeriodView.monthly);
    expect(find.text('Total mensual: Sin presupuesto'), findsOneWidget);
    await press('Mes anterior');
    expect(find.text('Total mensual: −123,00 €'), findsOneWidget);
    await press('Mes anterior');
    expect(find.text('0,00 € (registrado)'), findsOneWidget);
    expect(find.text('Total mensual: 0,00 €'), findsOneWidget);
    await press('Mes anterior');
    expect(
      find.text('Histórico archivado · incluido en el total'),
      findsOneWidget,
    );
    expect(find.text('Total mensual: −200,00 €'), findsOneWidget);
    await press('Mes siguiente');

    for (final label in [
      'Real',
      'Indicadores',
      'Estado',
      'Patrimonio',
      'Presupuesto',
    ]) {
      await destination(label);
      expect(session.period, NavigationPeriod(2026, 1));
      expect(nav().canPop(), isFalse);
      if (label == 'Real' || label == 'Estado' || label == 'Indicadores') {
        // Solo se verifica periodo del marcador; no hay informe financiero.
        expect(find.textContaining('€'), findsNothing);
      }
    }
    await year('2035');
    expect(session.period, NavigationPeriod(2035, 1));
    expect(find.text('Total mensual: Sin presupuesto'), findsOneWidget);
    await destination('Patrimonio');
    expect(find.text('Sin dato: falta foto patrimonial'), findsOneWidget);
    await tap(find.byTooltip('Gestión'));
    await press('Movimientos');
    expect(list().from.value, '2035-01-01');
    expect(list().page!.subtotalCents, 0);
    expect(list().page!.records, isEmpty);
    nav().pop();
    await settle();
    expect(session.period, NavigationPeriod(2035, 1));
    await year('1980');
    expect(find.text('Sin dato: falta foto patrimonial'), findsOneWidget);
    expect((await io(data.database.readState)).revision, before.revision);

    now = DateTime.utc(2026, 1, 31, 23, 30); // Madrid ya es febrero.
    await press('Mes actual');
    expect(session.context.destination, SessionDestination.wealth);
    expect(session.period, NavigationPeriod(2026, 2));
    expect(find.text('Patrimonio neto: 0,00\u00a0€'), findsOneWidget);
    await press('Mes anterior');

    // El filtro explícito sigue siendo local al listado y vuelve intacto.
    nav().pushNamed(
      '/movimientos?desde=2026-01-01&hasta=2026-01-02&concepto=Enero',
    );
    await settle();
    final originList = list();
    originList.selectPage();
    expect(originList.page!.subtotalCents, 30000);
    await press('Abrir Enero sintético');
    await press('Editar');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Concepto'),
      'Borrador sintético',
    );
    await press('Cancelar');
    await press('Seguir editando');
    expect(find.text('Borrador sintético'), findsOneWidget);
    await press('Cancelar');
    await press('Descartar cambios');
    await press('Volver a Movimientos');
    expect(list(), same(originList));
    expect(list().selected, contains(data.movementId));
    expect(list().concept, 'Enero');
    expect(list().context.focus, data.movementId);
    expect((await io(data.database.readState)).revision, before.revision);

    await press('Abrir Enero sintético');
    await press('Editar');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Fecha de valor · AAAA-MM-DD'),
      '2026-02-01',
    );
    await press('Guardar movimiento');
    expect(session.period, NavigationPeriod(2026, 1));
    expect(list(), same(originList));
    expect(list().from.value, '2026-01-01');
    expect(list().until!.value, '2026-01-02');
    expect(list().page!.records, isEmpty);
    expect(list().selected, isEmpty);
    await press('Ver mes');
    expect(list().from.value, '2026-02-01');
    expect(list().page!.subtotalCents, 30000);
    expect(session.period, NavigationPeriod(2026, 1));
    nav().pop();
    await settle();
    expect(list(), same(originList));
    expect(list().concept, 'Enero');
    nav().pop();
    await settle();
    expect(session.period, NavigationPeriod(2026, 1));
    expect((await io(data.database.readState)).revision, before.revision + 1);

    // Partida fuera de mes: borrador protegido y posición/foco del origen.
    await destination('Presupuesto');
    final detail = find.descendant(
      of: find.byKey(ValueKey(data.focusCategoryId)),
      matching: find.widgetWithText(TextButton, 'Abrir alta'),
    );
    await tester.ensureVisible(detail);
    await tester.pumpAndSettle();
    final scroll = tester
        .widget<SingleChildScrollView>(
          find.ancestor(
            of: detail,
            matching: find.byType(SingleChildScrollView),
          ),
        )
        .controller!;
    final offset = scroll.offset;
    expect(offset, greaterThan(0));
    await tap(detail);
    await tester.enterText(
      find.widgetWithText(TextField, 'Importe firmado (€)'),
      '-25',
    );
    await press('Cancelar');
    await press('Seguir editando');
    expect(find.text('-25'), findsOneWidget);
    await press('Cancelar');
    await press('Descartar cambios');
    expect(session.period, NavigationPeriod(2026, 1));
    expect(scroll.offset, closeTo(offset, 1));
    expect(session.context.focus, data.focusCategoryId);
    expect(tester.widget<TextButton>(detail).focusNode!.hasFocus, isTrue);
    await tap(detail);
    await tester.enterText(find.byKey(const Key('budget-period')), '2026-02');
    await tester.enterText(
      find.widgetWithText(TextField, 'Importe firmado (€)'),
      '0',
    );
    await press('Guardar partida');
    expect(session.period, NavigationPeriod(2026, 1));
    expect(scroll.offset, closeTo(offset, 1));
    await press('Ver mes');
    expect(session.period, NavigationPeriod(2026, 2));
    expect(find.text('0,00 € (registrado)'), findsOneWidget);
    nav().pop();
    await settle();
    expect(session.period, NavigationPeriod(2026, 1));
    expect(scroll.offset, closeTo(offset, 1));
    expect(session.context.focus, data.focusCategoryId);
    await press('Mes siguiente');
    expect(session.period, NavigationPeriod(2026, 2));
    expect(scroll.offset, 0);
    expect(session.context.focus, isNull);
    expect((await io(data.database.readState)).revision, before.revision + 2);

    // Una sesión nueva vuelve a Estado/Madrid incluso sobre el mismo SQLite.
    await tester.pumpWidget(const SizedBox.shrink());
    await settle();
    await tester.pumpWidget(
      AutofinanceApp(
        navigationClock: () => now,
        wealth: () async => data.wealth,
      ),
    );
    await settle();
    expect(find.text('Periodo de consulta: 2026-02'), findsOneWidget);
    expect(find.text('Estado del mes'), findsOneWidget);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    session.dispose();
    await io(data.close);
  }
}
