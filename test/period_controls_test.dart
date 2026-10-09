import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/budget_factory.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/app/navigation/period_controls.dart';
import 'package:myautofinance/app/wealth_management_factory.dart';
import 'package:myautofinance/features/budget/presentation/budget_source.dart';
import 'package:myautofinance/features/movements/movements.dart';

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder get yearField => find.byKey(const Key('period-year'));

Future<void> applyYear(WidgetTester tester, String year) async {
  await tester.enterText(yearField, year);
  await tap(tester, find.text('Ir al periodo'));
}

Future<void> chooseMonth(WidgetTester tester, String month) async {
  await tap(tester, find.byType(DropdownButtonFormField<int>));
  await tester.scrollUntilVisible(
    find.text(month),
    80,
    scrollable: find.byType(Scrollable).last,
  );
  await tap(tester, find.text(month).last);
}

void main() {
  testWidgets('Controles mensuales: Madrid, cruce de año y elección directa', (
    tester,
  ) async {
    final session = NavigationSession(
      clock: () => DateTime.utc(2026, 12, 31, 23, 30),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(AutofinanceApp(navigationSession: session));
    expect(session.period, NavigationPeriod(2027, 1));
    expect(find.text('Periodo de consulta: 2027-01'), findsOneWidget);
    await tap(tester, find.text('Mes anterior'));
    expect(session.period, NavigationPeriod(2026, 12));
    await tap(tester, find.text('Mes siguiente'));
    expect(session.period, NavigationPeriod(2027, 1));
    await applyYear(tester, '2031');
    expect(session.period, NavigationPeriod(2031, 1));
    await chooseMonth(tester, 'septiembre');
    await tap(tester, find.text('Ir al periodo'));
    expect(session.period, NavigationPeriod(2031, 9));
    await applyYear(tester, '1980');
    expect(session.period, NavigationPeriod(1980, 9));
    await tap(tester, find.text('Mes actual'));
    expect(session.period, NavigationPeriod(2027, 1));
    expect(find.textContaining('€'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cinco pestañas conservan periodo y no forman pila de detalles', (
    tester,
  ) async {
    final session = NavigationSession(clock: () => DateTime.utc(2026, 10, 9));
    addTearDown(session.dispose);
    await tester.pumpWidget(AutofinanceApp(navigationSession: session));
    await applyYear(tester, '2031');
    await chooseMonth(tester, 'agosto');
    await tap(tester, find.text('Ir al periodo'));
    for (final destination in [
      SessionDestination.wealth,
      SessionDestination.budget,
      SessionDestination.actual,
      SessionDestination.indicators,
      SessionDestination.status,
    ]) {
      await tap(
        tester,
        find.byKey(ValueKey('destination-${destination.name}')),
      );
      expect(session.context.destination, destination);
      expect(session.period, NavigationPeriod(2031, 8));
      expect(find.byType(PeriodControls), findsOneWidget);
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
        false,
      );
      if (destination.defaultView == PeriodView.annual) {
        expect(session.context.annualPeriod.year, 2031);
        expect(session.context.annualPeriod.focusedMonth, 8);
        expect(
          find.text('Año de consulta: 2031 · Mes enfocado: 2031-08'),
          findsOneWidget,
        );
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Año anual recupera memoria; selección explícita prevalece', (
    tester,
  ) async {
    final session = NavigationSession(clock: () => DateTime.utc(2026, 10, 9));
    addTearDown(session.dispose);
    await tester.pumpWidget(AutofinanceApp(navigationSession: session));
    await tap(tester, find.byKey(const ValueKey('destination-actual')));
    await applyYear(tester, '2031');
    expect(session.period, NavigationPeriod(2031, 1));
    await chooseMonth(tester, 'marzo');
    await tap(tester, find.text('Ir al periodo'));
    await tap(tester, find.text('Año anterior'));
    expect(session.period, NavigationPeriod(2030, 1));
    await tap(tester, find.text('Año siguiente'));
    expect(session.period, NavigationPeriod(2031, 3));
    await applyYear(tester, '2026');
    expect(session.period, NavigationPeriod(2026, 10));
    await applyYear(tester, '2031');
    await chooseMonth(tester, 'julio');
    await tap(tester, find.text('Ir al periodo'));
    expect(session.period, NavigationPeriod(2031, 7));
    await tap(tester, find.text('Mes actual'));
    expect(session.context.destination, SessionDestination.actual);
    expect(session.period, NavigationPeriod(2026, 10));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Años inválidos y límites mensuales/anuales no desbordan', (
    tester,
  ) async {
    final session = NavigationSession(clock: () => DateTime.utc(2026, 1, 1));
    addTearDown(session.dispose);
    await tester.pumpWidget(AutofinanceApp(navigationSession: session));
    for (final invalid in ['0', '10000', 'abc', '']) {
      await applyYear(tester, invalid);
      expect(find.text('Introduce un año entre 1 y 9999.'), findsOneWidget);
      expect(session.period, NavigationPeriod(2026, 1));
    }
    await applyYear(tester, '1');
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Mes anterior'))
          .onPressed,
      isNull,
    );
    await applyYear(tester, '9999');
    await chooseMonth(tester, 'diciembre');
    await tap(tester, find.text('Ir al periodo'));
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Mes siguiente'))
          .onPressed,
      isNull,
    );
    await tap(tester, find.byKey(const ValueKey('destination-actual')));
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Año siguiente'))
          .onPressed,
      isNull,
    );
    await applyYear(tester, '1');
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Año anterior'))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cambiar tamaño mantiene ruta, selección y entrada sin aplicar', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = NavigationSession(clock: () => DateTime.utc(2026, 10, 9));
    addTearDown(session.dispose);
    await tester.pumpWidget(AutofinanceApp(navigationSession: session));
    final route = ModalRoute.of(tester.element(yearField));
    await tester.enterText(yearField, '2035');
    for (final width in [320.0, 840.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 1200);
      await tester.pumpAndSettle();
      expect(ModalRoute.of(tester.element(yearField)), same(route));
      expect(tester.widget<TextField>(yearField).controller!.text, '2035');
      expect(session.period, NavigationPeriod(2026, 10));
      expect(tester.takeException(), isNull);
    }
    await tap(tester, find.text('Ir al periodo'));
    expect(session.period, NavigationPeriod(2035, 10));
  });

  testWidgets('320 px y texto 200 %: controles operables por teclado', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 1400);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final session = NavigationSession(clock: () => DateTime.utc(2026, 10, 9));
    addTearDown(session.dispose);
    await tester.pumpWidget(AutofinanceApp(navigationSession: session));
    await tester.enterText(yearField, '2031');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(session.period, NavigationPeriod(2031, 10));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tap(tester, find.text('Mes siguiente'));
    expect(session.period, NavigationPeriod(2031, 11));
    expect(tester.takeException(), isNull);
  });

  group('Rutas con SQLite sintético', () {
    late LocalDatabase db;
    late CategoryReadInvalidation invalidation;
    late BudgetSource budgets;
    late CategoryDetails category;
    late NavigationSession session;

    setUp(() async {
      db = LocalDatabase(
        NativeDatabase.memory(
          setup: (sqlite) => sqlite.execute('PRAGMA foreign_keys=ON'),
        ),
      );
      invalidation = CategoryReadInvalidation();
      final categories = createCategoryManagement(
        database: db,
        invalidation: invalidation,
      );
      category = await categories.create(
        name: 'Hogar sintético',
        isIncome: false,
      );
      budgets = createBudgetSource(db, invalidation);
      session = NavigationSession(clock: () => DateTime.utc(2026, 1, 9));
    });

    tearDown(() async {
      session.dispose();
      await invalidation.close();
      await db.close();
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    Future<void> boot(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 1400);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        AutofinanceApp(
          navigationSession: session,
          budgets: () async => budgets,
          wealth: () async => createWealthManagement(database: db),
        ),
      );
      await settle(tester);
    }

    testWidgets(
      'Patrimonio y presupuesto tienen un selector; visitar no escribe',
      (tester) async {
        await boot(tester);
        final revision = (await tester.runAsync(db.readState))!.revision;
        await tap(tester, find.byKey(const ValueKey('destination-wealth')));
        await settle(tester);
        expect(find.byType(PeriodControls), findsOneWidget);
        expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
        expect(find.text('Aplicar año'), findsNothing);
        await applyYear(tester, '2031');
        await settle(tester);
        expect(session.period, NavigationPeriod(2031, 1));
        expect(find.text('Sin dato: falta foto patrimonial'), findsOneWidget);
        await tap(tester, find.widgetWithText(TextButton, 'Presupuesto'));
        await settle(tester);
        expect(session.context.view, PeriodView.monthly);
        expect(find.byType(PeriodControls), findsOneWidget);
        expect(find.text('Mes siguiente'), findsOneWidget);
        expect(find.text('Total mensual: Sin presupuesto'), findsOneWidget);
        await tap(tester, find.text('Mes anterior'));
        await settle(tester);
        expect(session.period, NavigationPeriod(2030, 12));
        await tap(tester, find.widgetWithText(TextButton, 'Real'));
        expect(session.context.annualPeriod.focusedMonth, 12);
        expect((await tester.runAsync(db.readState))!.revision, revision);
      },
    );

    testWidgets(
      'Borrador bloquea periodo/pestaña y sobrevive al cambio de tamaño',
      (tester) async {
        await boot(tester);
        final revision = (await tester.runAsync(db.readState))!.revision;
        await tap(tester, find.byKey(const ValueKey('destination-budget')));
        await settle(tester);
        final cell = find.descendant(
          of: find.byKey(ValueKey(category.node.id)),
          matching: find.widgetWithText(TextButton, 'Sin presupuesto'),
        );
        await tap(tester, cell);
        await tester.enterText(
          find.byKey(const Key('budget-cell-input')),
          '-250',
        );
        await tap(tester, find.text('Mes siguiente'));
        expect(find.text('Hay cambios sin guardar'), findsOneWidget);
        await tap(tester, find.text('Seguir editando'));
        expect(session.period, NavigationPeriod(2026, 1));
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('budget-cell-input')))
              .controller!
              .text,
          '-250',
        );
        await chooseMonth(tester, 'marzo');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(session.period, NavigationPeriod(2026, 1));
        expect(
          tester
              .widget<DropdownButtonFormField<int>>(
                find.byType(DropdownButtonFormField<int>),
              )
              .initialValue,
          1,
        );
        expect(find.byKey(const Key('budget-cell-input')), findsOneWidget);
        await tap(tester, find.widgetWithText(TextButton, 'Real'));
        await tap(tester, find.text('Seguir editando'));
        expect(session.context.destination, SessionDestination.budget);
        final route = ModalRoute.of(tester.element(yearField));
        await tester.enterText(yearField, '2035');
        tester.view.physicalSize = const Size(320, 1400);
        await settle(tester);
        expect(ModalRoute.of(tester.element(yearField)), same(route));
        expect(tester.widget<TextField>(yearField).controller!.text, '2035');
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('budget-cell-input')))
              .controller!
              .text,
          '-250',
        );
        await tap(tester, find.text('Mes siguiente'));
        await tap(tester, find.text('Descartar cambios'));
        await settle(tester);
        expect(session.period, NavigationPeriod(2026, 2));
        expect(find.byKey(const Key('budget-cell-input')), findsNothing);
        expect((await tester.runAsync(db.readState))!.revision, revision);
      },
    );

    testWidgets('Gestión conserva entradas y retorna al periodo cambiado', (
      tester,
    ) async {
      await boot(tester);
      await applyYear(tester, '2031');
      await tap(tester, find.text('Gestión'));
      for (final label in [
        'Importar CSV',
        'Importar XLS',
        'Historial de importaciones',
        'Movimientos',
        'Pendientes de categorizar',
        'Categorías',
        'Fichas',
        'Copia en Drive',
        'Copias locales',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tap(tester, find.text('Fichas'));
      await settle(tester);
      await tap(tester, find.text('Volver al origen'));
      await settle(tester);
      expect(session.period, NavigationPeriod(2031, 1));
      expect(find.text('Periodo de consulta: 2031-01'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('destination-wealth')));
      await settle(tester);
      final route = ModalRoute.of(tester.element(yearField));
      await tester.enterText(yearField, '1985');
      tester.view.physicalSize = const Size(320, 1400);
      await settle(tester);
      expect(ModalRoute.of(tester.element(yearField)), same(route));
      expect(tester.widget<TextField>(yearField).controller!.text, '1985');
      await tap(tester, find.text('Ir al periodo'));
      await settle(tester);
      expect(session.period, NavigationPeriod(1985, 1));
    });
  });
}
