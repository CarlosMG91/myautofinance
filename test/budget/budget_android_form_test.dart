import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/budget_factory.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/navigation/app_router.dart';
import 'package:myautofinance/app/regional.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/budget/presentation/budget_source.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';

void main() {
  final january = BudgetMonth(2026, 1);
  late Directory directory;
  late File file;
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
    await tester.pumpAndSettle();
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(finder));
    await settle(tester);
  }

  Future<void> boot(
    WidgetTester tester, {
    String id = 'nueva',
    double scale = 1,
    BudgetLoader? load,
  }) async {
    await tester.pumpWidget(const SizedBox());
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
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
            RouteSettings(name: '/presupuesto/partidas/$id?a=2026&m=01'),
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

  Future<void> pick(WidgetTester tester, CategoryDetails category) async {
    await tap(tester, find.text('Seleccionar categoría'));
    await tester.scrollUntilVisible(
      find.text(category.path),
      120,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    await tap(tester, find.text(category.path));
    await tap(tester, find.widgetWithText(FilledButton, 'Seleccionar'));
  }

  String field(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

  Future<List<BudgetRecord>> records(WidgetTester tester) async =>
      (await tester.runAsync(() => SqliteBudgetRepository(db).list(january)))!;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('budget-103-synthetic-');
    file = File('${directory.path}/test.sqlite');
    db = LocalDatabase(
      NativeDatabase(
        file,
        setup: (sqlite) => sqlite.execute('PRAGMA foreign_keys=ON'),
      ),
    );
    invalidation = CategoryReadInvalidation();
    categories = createCategoryManagement(
      database: db,
      invalidation: invalidation,
    );
    root = await categories.create(name: 'Hogar', isIncome: false);
    child = await categories.create(name: 'Café', parentId: root.node.id);
    final other = await categories.create(name: 'Ocio', isIncome: false);
    sibling = await categories.create(name: 'Café', parentId: other.node.id);
    source = createBudgetSource(db, invalidation);
  });
  tearDown(() async {
    await invalidation.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  testWidgets('Alta a 320px/200%, UUID/ruta, cero y reapertura SQLite', (
    tester,
  ) async {
    await boot(tester, scale: 2);
    await tester.enterText(find.byKey(const Key('budget-form-amount')), '0');
    await tap(tester, find.text('Guardar partida'));
    expect(find.text('Selecciona una categoría.'), findsOneWidget);
    await pick(tester, sibling);
    expect(find.text('Categoría: Ocio / Café'), findsOneWidget);
    for (final button in find.byType(ButtonStyleButton).evaluate()) {
      final size = tester.getSize(find.byWidget(button.widget));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
    }
    expect(await records(tester), isEmpty);
    await tap(tester, find.text('Guardar partida'));
    final saved = (await records(tester)).single;
    expect(saved.data.categoryId, sibling.node.id);
    expect(saved.data.amountCents, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
    db = LocalDatabase(
      NativeDatabase(
        file,
        setup: (sqlite) => sqlite.execute('PRAGMA foreign_keys=ON'),
      ),
    );
    final reopened = (await records(tester)).single;
    expect(reopened.id, saved.id);
    expect(reopened.data.amountCents, 0);
  });

  testWidgets(
    'Validación de mes/importe y cancelación del selector conservan entrada',
    (tester) async {
      await boot(tester, scale: 2);
      await tester.enterText(find.byKey(const Key('budget-period')), '2026-13');
      await tester.enterText(
        find.byKey(const Key('budget-form-amount')),
        '-1,234',
      );
      await tap(tester, find.text('Guardar partida'));
      expect(find.text('Usa un mes válido AAAA-MM.'), findsOneWidget);
      expect(find.textContaining('hasta dos decimales'), findsWidgets);
      await tap(tester, find.text('Seleccionar categoría'));
      await tap(tester, find.text('Cancelar'));
      expect(field(tester, 'budget-period'), '2026-13');
      expect(field(tester, 'budget-form-amount'), '-1,234');
      expect(await records(tester), isEmpty);
    },
  );

  for (final parentFirst in [true, false]) {
    testWidgets(
      'Conflicto Android, padre primero: $parentFirst, conserva borrador',
      (tester) async {
        final existing = parentFirst ? root : child;
        final requested = parentFirst ? child : root;
        final old = await source.management.create(
          month: january,
          categoryId: existing.node.id,
          amountCents: 0,
        );
        await boot(tester);
        await pick(tester, requested);
        await tester.enterText(
          find.byKey(const Key('budget-form-amount')),
          '-33.25',
        );
        await tap(tester, find.text('Guardar partida'));
        expect(
          find.textContaining('2026-01: ${requested.path} ↔ ${existing.path}'),
          findsOneWidget,
        );
        expect(field(tester, 'budget-form-amount'), '-33.25');
        await tap(tester, find.text('Reintentar'));
        expect((await records(tester)).single.id, old.id);
        await tester.enterText(
          find.byKey(const Key('budget-period')),
          '2026-02',
        );
        await tap(tester, find.text('Reintentar'));
        expect((await records(tester)).single.id, old.id);
        final february = (await tester.runAsync(
          () => SqliteBudgetRepository(db).list(BudgetMonth(2026, 2)),
        ))!;
        expect(february.single.data.amountCents, -3325);
      },
    );
  }

  testWidgets('Fallo de escritura y doble toque: reintento sin duplicados', (
    tester,
  ) async {
    await db.customStatement(
      "CREATE TEMP TRIGGER reject_budget BEFORE INSERT ON budgets BEGIN SELECT RAISE(ABORT,'synthetic'); END",
    );
    await boot(tester);
    await pick(tester, child);
    await tester.enterText(
      find.byKey(const Key('budget-form-amount')),
      '+12,50',
    );
    await tap(tester, find.text('Guardar partida'));
    expect(find.textContaining('No se pudo completar'), findsOneWidget);
    expect(field(tester, 'budget-form-amount'), '+12,50');
    expect(await records(tester), isEmpty);
    await tester.runAsync(
      () => db.customStatement('DROP TRIGGER reject_budget'),
    );
    await tester.ensureVisible(find.text('Reintentar'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Reintentar'));
      await tester.tap(find.text('Reintentar'));
    });
    await settle(tester);
    expect((await records(tester)).single.data.amountCents, 1250);
  });

  testWidgets(
    'Detalle importado archivado: edición de tres campos conserva toda la procedencia',
    (tester) async {
      await SqliteImportBatchRepository(db).create(
        sha256: 'a' * 64,
        source: ImportSource.historicalCsv,
        originalName: 'sintetico.csv',
        contractVersion: '1',
        movements: [],
        budgets: [
          ImportedBudget(
            7,
            BudgetInput(
              month: january,
              categoryId: child.node.id,
              amountCents: -100,
              concept: 'Concepto histórico',
              discretion: 'Necesario',
            ),
          ),
        ],
      );
      final old = (await SqliteBudgetRepository(db).list(january)).single;
      await categories.archive(child.node.id);
      await boot(tester, id: old.id, scale: 2);
      expect(
        find.textContaining('Archivada (se puede conservar)'),
        findsOneWidget,
      );
      await tap(tester, find.text('Editar'));
      await tester.enterText(find.byKey(const Key('budget-period')), '2026-02');
      await tester.enterText(find.byKey(const Key('budget-form-amount')), '0');
      await tap(tester, find.text('Guardar partida'));
      final kept = (await tester.runAsync(
        () => source.management.get(old.id),
      ))!;
      expect(kept.data.categoryId, child.node.id);
      await boot(tester, id: old.id);
      await tap(tester, find.text('Editar'));
      await tap(tester, find.text('Seleccionar categoría'));
      expect(find.text(child.path), findsNothing);
      await tap(tester, find.text(sibling.path));
      await tap(tester, find.widgetWithText(FilledButton, 'Seleccionar'));
      await tester.enterText(find.byKey(const Key('budget-period')), '2026-03');
      await tester.enterText(
        find.byKey(const Key('budget-form-amount')),
        '-25,50',
      );
      await tap(tester, find.text('Guardar partida'));
      final saved = (await tester.runAsync(
        () => source.management.get(old.id),
      ))!;
      expect(saved.id, old.id);
      expect(saved.data.month.value, '2026-03-01');
      expect(saved.data.categoryId, sibling.node.id);
      expect(saved.data.amountCents, -2550);
      expect(saved.data.concept, old.data.concept);
      expect(saved.data.discretion, old.data.discretion);
      expect(saved.batchId, old.batchId);
      expect(saved.importRowId, old.importRowId);
      expect(saved.sourceOrdinal, 7);
    },
  );

  testWidgets(
    'Atrás Android, cancelar y destinos preguntan antes de descartar',
    (tester) async {
      await boot(tester);
      await pick(tester, child);
      await tester.enterText(find.byKey(const Key('budget-form-amount')), '22');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('Hay cambios sin guardar'), findsOneWidget);
      await tap(tester, find.text('Seguir editando'));
      expect(field(tester, 'budget-form-amount'), '22');
      await tap(tester, find.text('Cancelar'));
      await tap(tester, find.text('Seguir editando'));
      await tap(tester, find.text('Real'));
      await tap(tester, find.text('Descartar cambios'));
      expect(find.byKey(const Key('budget-form-amount')), findsNothing);
      expect(await records(tester), isEmpty);
    },
  );

  testWidgets(
    'Borrado confirma la partida guardada y fallo conserva borrador sin reintentar guardado',
    (tester) async {
      final old = await source.management.create(
        month: january,
        categoryId: child.node.id,
        amountCents: 0,
      );
      await boot(tester, id: old.id, scale: 2);
      await tap(tester, find.text('Editar'));
      await pick(tester, sibling);
      await tester.enterText(
        find.byKey(const Key('budget-form-amount')),
        '-88',
      );
      await tap(tester, find.text('Eliminar partida'));
      expect(find.textContaining('2026-01 · ${child.path}'), findsOneWidget);
      await tap(tester, find.text('Cancelar').last);
      expect((await records(tester)).single.id, old.id);
      await tester.runAsync(
        () => db.customStatement(
          "CREATE TEMP TRIGGER reject_delete BEFORE DELETE ON budgets BEGIN SELECT RAISE(ABORT,'synthetic'); END",
        ),
      );
      await tap(tester, find.text('Eliminar partida'));
      await tap(tester, find.widgetWithText(FilledButton, 'Eliminar partida'));
      expect(find.textContaining('No se pudo completar'), findsOneWidget);
      expect(field(tester, 'budget-form-amount'), '-88');
      expect(find.text('Reintentar'), findsNothing);
      expect((await records(tester)).single.data.categoryId, child.node.id);
      await tester.runAsync(
        () => db.customStatement('DROP TRIGGER reject_delete'),
      );
      await tap(tester, find.text('Eliminar partida'));
      await tap(tester, find.widgetWithText(FilledButton, 'Eliminar partida'));
      expect(await records(tester), isEmpty);
    },
  );

  testWidgets(
    'Lectura fallida reintenta; sustitución de base bloquea escritura y conserva campos',
    (tester) async {
      var fail = true;
      var replaced = false;
      final otherIdentity = Object();
      await boot(
        tester,
        load: () async {
          if (fail) throw const BudgetFailure('Lectura sintética fallida');
          if (replaced) {
            return BudgetSource(
              query: source.query,
              management: source.management,
              categories: source.categories,
              identity: otherIdentity,
            );
          }
          return source;
        },
      );
      expect(find.byKey(const Key('budget-form-amount')), findsNothing);
      fail = false;
      await tap(tester, find.text('Reintentar'));
      await pick(tester, child);
      await tester.enterText(
        find.byKey(const Key('budget-form-amount')),
        '-10',
      );
      replaced = true;
      await tap(tester, find.text('Guardar partida'));
      expect(
        find.textContaining('La base local se ha sustituido'),
        findsOneWidget,
      );
      expect(field(tester, 'budget-form-amount'), '-10');
      expect(await records(tester), isEmpty);
    },
  );
}
