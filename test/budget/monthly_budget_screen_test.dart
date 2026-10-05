import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/budget_factory.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/navigation/app_router.dart';
import 'package:myautofinance/app/regional.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/budget/presentation/budget_ui.dart';
import 'package:myautofinance/features/budget/presentation/budget_source.dart';
import 'package:myautofinance/features/movements/movements.dart';

void main() {
  final january = BudgetMonth(2026, 1);
  late LocalDatabase db;
  late CategoryReadInvalidation invalidation;
  late CategoryManagement categories;
  late CategoryDetails root, child, sibling;
  late BudgetSource source;
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(finder));
    await settle(tester);
  }

  Finder cell(CategoryDetails category, String text) => find.descendant(
    of: find.byKey(ValueKey(category.node.id)),
    matching: find.widgetWithText(TextButton, text),
  );
  Future<void> boot(
    WidgetTester tester, {
    double width = 1440,
    double scale = 1,
    String route = '/presupuesto?a=2026&m=01',
    BudgetLoader? load,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1200);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: AppRegional.locale,
        supportedLocales: AppRegional.supportedLocales,
        localizationsDelegates: AppRegional.delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        onGenerateInitialRoutes: (_) => [
          AppRouter.generateRoute(
            RouteSettings(name: route),
            budgets: load ?? () async => source,
            categories: () async => categories,
          ),
        ],
        onGenerateRoute: (settings) => AppRouter.generateRoute(
          settings,
          budgets: load ?? () async => source,
          categories: () async => categories,
        ),
      ),
    );
    await settle(tester);
  }

  setUp(() async {
    db = LocalDatabase(
      NativeDatabase.memory(
        setup: (sqlite) => sqlite.execute('PRAGMA foreign_keys=ON'),
      ),
    );
    invalidation = CategoryReadInvalidation();
    categories = createCategoryManagement(
      database: db,
      invalidation: invalidation,
    );
    root = await categories.create(name: 'Hogar', isIncome: false);
    child = await categories.create(name: 'Alquiler', parentId: root.node.id);
    sibling = await categories.create(name: 'Mercado', parentId: root.node.id);
    source = createBudgetSource(db, invalidation);
  });
  tearDown(() async {
    await invalidation.close();
    await db.close();
  });

  test('Importe firmado exacto, coma/punto y límites int64', () {
    expect(parseBudgetAmount('−33,25'), -3325);
    expect(parseBudgetAmount('+0.00'), 0);
    expect(parseBudgetAmount('-92233720368547758,08'), -9223372036854775808);
    for (final bad in ['', '1,234', '1.000,00', '92233720368547758,08']) {
      expect(() => parseBudgetAmount(bad), throwsA(isA<BudgetFailure>()));
    }
  });

  testWidgets(
    'Intro confirma una sola celda; cero, vacío y foco no borran ni guardan en bloque',
    (tester) async {
      final old = await source.management.create(
        month: january,
        categoryId: child.node.id,
        amountCents: -70000,
      );
      await boot(tester);
      await tap(tester, cell(sibling, 'Sin presupuesto'));
      await tester.enterText(find.byKey(const Key('budget-cell-input')), '0');
      await tap(
        tester,
        find.text(
          'Cada confirmación guarda solo una partida. El subtotal de rama es de solo lectura.',
        ),
      );
      expect(
        await tester.runAsync(() => SqliteBudgetRepository(db).list(january)),
        hasLength(1),
      );
      await tester.tap(find.byKey(const Key('budget-cell-input')));
      await tester.runAsync(
        () => tester.testTextInput.receiveAction(TextInputAction.done),
      );
      await settle(tester);
      expect(find.text('Partida guardada'), findsOneWidget);
      final records = (await tester.runAsync(
        () => SqliteBudgetRepository(db).list(january),
      ))!;
      expect(records, hasLength(2));
      expect(
        records.singleWhere((r) => r.id == old.id).data.amountCents,
        -70000,
      );
      expect(
        records
            .singleWhere((r) => r.data.categoryId == sibling.node.id)
            .data
            .amountCents,
        0,
      );
      expect(find.text('Subtotal de rama: −700,00 €'), findsWidgets);
      await tap(tester, cell(sibling, '0,00 € (registrado)'));
      await tester.enterText(find.byKey(const Key('budget-cell-input')), '');
      await tap(tester, find.text('Confirmar celda'));
      expect(find.textContaining('Vaciar no elimina'), findsWidgets);
      expect(
        (await tester.runAsync(
          () => SqliteBudgetRepository(db).list(january),
        ))!,
        hasLength(2),
      );
    },
  );

  testWidgets(
    'Conflicto padre/hijo muestra mes/rutas y mantiene el borrador; hermanas válidas',
    (tester) async {
      await source.management.create(
        month: january,
        categoryId: child.node.id,
        amountCents: 0,
      );
      await boot(tester);
      await tap(tester, cell(root, 'Sin presupuesto'));
      await tester.enterText(
        find.byKey(const Key('budget-cell-input')),
        '-33,25',
      );
      await tap(tester, find.text('Confirmar celda'));
      expect(
        find.textContaining('2026-01: Hogar ↔ Hogar / Alquiler'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('budget-cell-input')))
            .controller!
            .text,
        '-33,25',
      );
      expect(
        (await tester.runAsync(
          () => SqliteBudgetRepository(db).list(january),
        ))!,
        hasLength(1),
      );
      await tap(tester, find.text('Cancelar'));
      await tap(tester, find.text('Descartar cambios'));
      await tap(tester, cell(sibling, 'Sin presupuesto'));
      await tester.enterText(find.byKey(const Key('budget-cell-input')), '0');
      await tap(tester, find.text('Confirmar celda'));
      expect(
        (await tester.runAsync(
          () => SqliteBudgetRepository(db).list(january),
        ))!,
        hasLength(2),
      );
    },
  );

  testWidgets('Fallo SQLite hace rollback y reintentar crea solo una partida', (
    tester,
  ) async {
    await db.customStatement(
      "CREATE TEMP TRIGGER reject_budget BEFORE INSERT ON budgets BEGIN SELECT RAISE(ABORT,'synthetic'); END",
    );
    await boot(tester);
    await tap(tester, cell(child, 'Sin presupuesto'));
    await tester.enterText(
      find.byKey(const Key('budget-cell-input')),
      '-25.50',
    );
    await tap(tester, find.text('Confirmar celda'));
    expect(find.text('Partida guardada'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('budget-cell-input')))
          .controller!
          .text,
      '-25.50',
    );
    expect(
      (await tester.runAsync(() => SqliteBudgetRepository(db).list(january)))!,
      isEmpty,
    );
    await tester.runAsync(
      () => db.customStatement('DROP TRIGGER reject_budget'),
    );
    await tap(tester, find.text('Reintentar'));
    expect(
      (await tester.runAsync(() => SqliteBudgetRepository(db).list(january)))!,
      hasLength(1),
    );
  });

  testWidgets(
    'Salir o Gestión con cambios confirma; Esc conserva; descarte permite navegación',
    (tester) async {
      await boot(tester);
      await tap(tester, cell(child, 'Sin presupuesto'));
      await tester.enterText(find.byKey(const Key('budget-cell-input')), '12');
      await tap(tester, find.text('Estado'));
      expect(find.text('Hay cambios sin guardar'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.byKey(const Key('budget-cell-input')), findsOneWidget);
      await tap(tester, find.byTooltip('Gestión'));
      await tap(tester, find.text('Categorías'));
      expect(find.text('Hay cambios sin guardar'), findsOneWidget);
      await tap(tester, find.text('Seguir editando'));
      await tap(tester, find.text('Estado'));
      await tap(tester, find.text('Descartar cambios'));
      expect(find.text('Presupuesto mensual'), findsNothing);
      expect(
        (await tester.runAsync(
          () => SqliteBudgetRepository(db).list(january),
        ))!,
        isEmpty,
      );
    },
  );

  testWidgets(
    'Detalle cambia mes/categoría/importe y conserva metadatos; retorno y borrado confirmado',
    (tester) async {
      final record = await SqliteBudgetRepository(db).create(
        BudgetInput(
          month: january,
          categoryId: child.node.id,
          amountCents: -1,
          concept: 'Concepto histórico',
          discretion: 'Texto histórico',
        ),
      );
      await boot(tester);
      await tap(tester, cell(child, 'Abrir detalle'));
      expect(find.textContaining('Concepto histórico'), findsOneWidget);
      await tap(tester, find.text('Editar'));
      await tester.enterText(find.byKey(const Key('budget-period')), '2026-02');
      await tester.enterText(find.byKey(const Key('budget-form-amount')), '0');
      await tap(tester, find.text('Seleccionar categoría'));
      await tap(tester, find.text('Hogar / Mercado'));
      await tap(tester, find.text('Seleccionar'));
      await tap(tester, find.text('Guardar partida'));
      final saved = (await tester.runAsync(
        () => source.management.get(record.id),
      ))!;
      expect(saved.data.month.value, '2026-02-01');
      expect(saved.data.categoryId, sibling.node.id);
      expect(saved.data.amountCents, 0);
      expect(saved.data.concept, 'Concepto histórico');
      expect(saved.data.discretion, 'Texto histórico');
      expect(find.text('Ver mes'), findsOneWidget);
      await tap(tester, find.text('Ver mes'));
      await tap(tester, cell(sibling, 'Abrir detalle'));
      await tap(tester, find.text('Eliminar partida'));
      await tap(tester, find.text('Cancelar').last);
      expect(
        await tester.runAsync(() => source.management.get(record.id)),
        isNotNull,
      );
      await tap(tester, find.text('Eliminar partida'));
      await tap(tester, find.widgetWithText(FilledButton, 'Eliminar partida'));
      expect(cell(sibling, 'Sin presupuesto'), findsOneWidget);
      expect(
        (await tester.runAsync(
          () => SqliteBudgetRepository(db).list(BudgetMonth(2026, 2)),
        ))!,
        isEmpty,
      );
    },
  );

  testWidgets('320px con texto 200% y error de lectura sin totales ficticios', (
    tester,
  ) async {
    var failed = true;
    await boot(
      tester,
      width: 320,
      scale: 2,
      load: () async {
        if (failed) throw const BudgetFailure('Fallo sintético de lectura');
        return source;
      },
    );
    expect(find.textContaining('Total mensual:'), findsNothing);
    failed = false;
    await tap(tester, find.text('Reintentar'));
    expect(find.text('Total mensual: Sin presupuesto'), findsOneWidget);
    await tap(tester, cell(child, 'Abrir alta'));
    await tester.enterText(find.byKey(const Key('budget-form-amount')), '0');
    await tap(tester, find.text('Guardar partida'));
    expect(
      (await tester.runAsync(() => SqliteBudgetRepository(db).list(january)))!,
      hasLength(1),
    );
  });

  testWidgets(
    'Cierre nativo y diálogo abierto conservan el borrador; retorno restaura foco',
    (tester) async {
      await boot(tester);
      await tap(tester, cell(child, 'Sin presupuesto'));
      await tester.enterText(find.byKey(const Key('budget-cell-input')), '10');
      final response = tester.binding.handleRequestAppExit();
      await settle(tester);
      expect(find.text('Hay cambios sin guardar'), findsOneWidget);
      expect(
        await tester.binding.handleRequestAppExit(),
        AppExitResponse.cancel,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(await response, AppExitResponse.cancel);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('budget-cell-input')))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await tap(tester, find.text('Confirmar celda'));
      expect(
        tester.widget<TextButton>(cell(child, '+10,00 €')).focusNode!.hasFocus,
        isTrue,
      );
      await tap(tester, cell(child, 'Abrir detalle'));
      await tap(tester, find.text('Cancelar'));
      expect(find.text('Presupuesto mensual'), findsOneWidget);
    },
  );

  testWidgets(
    'Histórico archivado cuenta una vez y se corrige conservando la categoría',
    (tester) async {
      final record = await source.management.create(
        month: january,
        categoryId: child.node.id,
        amountCents: -100,
      );
      await categories.archive(child.node.id);
      await boot(tester, width: 1024, scale: 2);
      expect(
        find.text('Histórico archivado · incluido en el total'),
        findsOneWidget,
      );
      expect(find.text('Total mensual: −1,00 €'), findsOneWidget);
      await tap(tester, cell(child, 'Abrir detalle'));
      await tap(tester, find.text('Editar'));
      await tester.enterText(find.byKey(const Key('budget-form-amount')), '0');
      await tap(tester, find.text('Guardar partida'));
      final saved = (await tester.runAsync(
        () => source.management.get(record.id),
      ))!;
      expect(saved.data.categoryId, child.node.id);
      expect(saved.data.amountCents, 0);
      expect(find.text('Total mensual: 0,00 €'), findsOneWidget);
    },
  );

  testWidgets(
    'SQLite de archivo: celda guardada sobrevive cierre y reapertura',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('budget-102-synthetic-'),
      ))!;
      final file = File('${directory.path}/test.sqlite');
      await tester.runAsync(db.close);
      final fileDb = LocalDatabase(
        NativeDatabase(
          file,
          setup: (sqlite) => sqlite.execute('PRAGMA foreign_keys=ON'),
        ),
      );
      try {
        final fileCategories = createCategoryManagement(
          database: fileDb,
          invalidation: invalidation,
        );
        final category = (await tester.runAsync(
          () => fileCategories.create(name: 'Ahorro', isIncome: false),
        ))!;
        source = createBudgetSource(fileDb, invalidation);
        await boot(tester);
        await tap(tester, cell(category, 'Sin presupuesto'));
        await tester.enterText(
          find.byKey(const Key('budget-cell-input')),
          '-123,45',
        );
        await tap(tester, find.text('Confirmar celda'));
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(fileDb.close);
        final reopened = LocalDatabase(
          NativeDatabase(
            file,
            setup: (sqlite) => sqlite.execute('PRAGMA foreign_keys=ON'),
          ),
        );
        try {
          final records = (await tester.runAsync(
            () => SqliteBudgetRepository(reopened).list(january),
          ))!;
          expect(records.single.data.amountCents, -12345);
        } finally {
          await tester.runAsync(reopened.close);
        }
      } finally {
        await tester.runAsync(fileDb.close);
        await tester.runAsync(() => directory.delete(recursive: true));
      }
    },
  );
}
