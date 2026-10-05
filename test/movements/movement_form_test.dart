import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/app/movement_list_factory.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/navigation/app_router.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/movements/presentation/movement_form_screen.dart';
import 'package:myautofinance/features/movements/presentation/movement_editor_source.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  late Directory directory;
  late LocalDatabaseStore store;
  late LocalDatabase db;
  late CategoryReadInvalidation invalidation;
  late MovementEditorSource source;
  late String account, category;
  MovementRecord? saved;
  var deleted = 0, returned = 0, calls = 0, fail = false;
  Completer<MovementEditorSource>? pending;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'movement-form-synthetic-',
    );
    store = LocalDatabaseStore(supportDirectory: () async => directory);
    db = await store.open();
    invalidation = CategoryReadInvalidation();
    account = (await SqliteAccountRepository(db).create(
      name: 'Diaria sintética',
      kind: AccountKind.account,
      activeFrom: Month(2026, 3),
      activeThrough: Month(2026, 4),
      liquidity: Liquidity.liquid,
    )).id;
    await SqliteAccountRepository(db).create(
      name: 'Cartera excluida',
      kind: AccountKind.portfolio,
      activeFrom: Month(2026, 1),
      liquidity: Liquidity.liquid,
    );
    category = (await SqliteCategoryRepository(
      db,
    ).create(name: 'Ocio sintético')).id;
    source = await createMovementListSource(db, invalidation).editor!();
    saved = null;
    deleted = returned = calls = 0;
    fail = false;
    pending = null;
  });
  tearDown(() async {
    await invalidation.close();
    await store.close();
    await directory.delete(recursive: true);
  });
  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<T> io<T>(WidgetTester t, Future<T> Function() action) async =>
      await t.runAsync(action) as T;
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 30; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await t.pump(const Duration(milliseconds: 20));
    }
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  Future<void> tap(WidgetTester t, String label) async {
    final target = find.text(label).last;
    await t.ensureVisible(target);
    await t.tap(target);
    await settle(t);
  }

  Future<void> enter(WidgetTester t, String label, String value) async {
    await t.ensureVisible(field(label));
    await t.enterText(field(label), value);
    await t.pump();
  }

  Future<void> mount(
    WidgetTester t, {
    String? id,
    Future<CategoryDetails?> Function(String?)? pick,
  }) async {
    await t.pumpWidget(
      MaterialApp(
        home: MovementFormScreen(
          load: () async {
            calls++;
            if (fail) {
              throw const MovementFailure('Fallo sintético de escritura.');
            }
            return pending == null ? source : await pending!.future;
          },
          initialDate: ValueDate(2026, 3, 1),
          id: id,
          onReturn: () => returned++,
          onSaved: (r) => saved = r,
          onDeleted: () => deleted++,
          selectCategory: pick ?? (_) async => null,
        ),
      ),
    );
    await settle(t);
  }

  Future<void> chooseAccount(WidgetTester t) async {
    final dropdown = find.byType(DropdownButtonFormField<String>);
    await t.ensureVisible(dropdown);
    await t.tap(dropdown);
    await t.pumpAndSettle();
    await t.tap(
      find.text('Diaria sintética · ${account.substring(0, 8)}').last,
    );
    await t.pumpAndSettle();
  }

  Future<MovementRecord> existing() => source.management.create(
    accountId: account,
    valueDate: '2026-03-15',
    concept: 'Café sintético',
    amount: '-12,50',
    categoryId: category,
    discretion: 'capricho',
  );

  testWidgets(
    'Alta valida sin perder borrador, espera persistencia y evita doble envío',
    (t) async {
      await mount(t);
      await enter(t, 'Concepto', 'Alta sintética');
      await enter(t, 'Importe firmado (EUR)', '0');
      await chooseAccount(t);
      await tap(t, 'Guardar movimiento');
      expect(find.textContaining('distinto de cero'), findsOneWidget);
      expect(
        t.widget<TextField>(field('Concepto')).controller!.text,
        'Alta sintética',
      );
      await enter(t, 'Importe firmado (EUR)', '+2,51');
      pending = Completer<MovementEditorSource>();
      await tap(t, 'Guardar movimiento');
      expect(saved, isNull);
      final button = t.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Guardando…'),
      );
      expect(button.onPressed, isNull);
      expect(calls, 2);
      pending!.complete(source);
      await settle(t);
      expect(saved!.data.amountCents, 251);
      final rows = await io(t, () => source.management.get(saved!.id));
      expect(rows.data.concept, 'Alta sintética');
    },
  );
  testWidgets(
    'Edición conserva categoría archivada y retira discrecionalidad explícitamente',
    (t) async {
      final old = await io(t, existing);
      await io(
        t,
        () =>
            SqliteCategoryRepository(db).setArchived(category, archived: true),
      );
      await mount(t, id: old.id);
      expect(find.textContaining('Archivada'), findsOneWidget);
      await tap(t, 'Editar');
      await enter(t, 'Concepto', 'Corregido');
      await enter(t, 'Discrecionalidad opcional', '');
      await tap(t, 'Guardar movimiento');
      expect(saved!.data.categoryId, category);
      expect(saved!.data.discretion, isNull);
      expect(saved!.data.amountCents, old.data.amountCents);
      expect(saved!.id, old.id);
    },
  );
  testWidgets(
    'Quitar categoría explícitamente; cancelar selector mantiene el borrador',
    (t) async {
      final old = await io(t, existing);
      await mount(t, id: old.id);
      await tap(t, 'Editar');
      await tap(t, 'Seleccionar categoría');
      expect(find.textContaining('Ocio sintético'), findsOneWidget);
      await tap(t, 'Quitar categoría');
      await tap(t, 'Guardar movimiento');
      expect(saved!.data.categoryId, isNull);
      expect(saved!.data.discretion, 'capricho');
    },
  );
  testWidgets('Fallo al guardar conserva campos y permite reintentar', (
    t,
  ) async {
    final old = await io(t, existing);
    await mount(t, id: old.id);
    await tap(t, 'Editar');
    await enter(t, 'Concepto', 'Borrador pendiente');
    fail = true;
    await tap(t, 'Guardar movimiento');
    expect(saved, isNull);
    expect(find.text('Fallo sintético de escritura.'), findsOneWidget);
    expect(
      (await io(t, () => source.management.get(old.id))).data.concept,
      old.data.concept,
    );
    expect(
      t.widget<TextField>(field('Concepto')).controller!.text,
      'Borrador pendiente',
    );
    fail = false;
    await tap(t, 'Guardar movimiento');
    expect(saved!.data.concept, 'Borrador pendiente');
  });
  testWidgets(
    'Cancelar/Esc borrado conserva datos; fallo conserva detalle; confirmar elimina',
    (t) async {
      final old = await io(t, existing);
      await mount(t, id: old.id);
      final before = (await io(t, db.readState)).revision;
      await tap(t, 'Borrar movimiento');
      expect(find.text('Borrar 1 movimiento'), findsOneWidget);
      expect(find.textContaining('UUID: ${old.id}'), findsWidgets);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(t);
      expect((await io(t, db.readState)).revision, before);
      expect(deleted, 0);
      await tap(t, 'Borrar movimiento');
      await tap(t, 'Cancelar');
      expect((await io(t, () => source.management.get(old.id))).id, old.id);
      await tap(t, 'Borrar movimiento');
      fail = true;
      await tap(t, 'Confirmar borrado');
      expect(deleted, 0);
      expect(find.text('Fallo sintético de escritura.'), findsOneWidget);
      fail = false;
      await tap(t, 'Borrar movimiento');
      await tap(t, 'Confirmar borrado');
      expect(deleted, 1);
      expect((await io(t, db.readState)).revision, before + 1);
      await io(t, () async {
        await expectLater(
          source.management.get(old.id),
          throwsA(isA<MovementFailure>()),
        );
      });
    },
  );
  testWidgets('Atrás con cambios conserva borrador o descarta sin escribir', (
    t,
  ) async {
    final old = await io(t, existing);
    await mount(t, id: old.id);
    await tap(t, 'Editar');
    await enter(t, 'Concepto', 'Sin guardar');
    await t.binding.handlePopRoute();
    await settle(t);
    expect(find.text('Hay cambios sin guardar'), findsOneWidget);
    await tap(t, 'Seguir editando');
    expect(returned, 0);
    expect(
      t.widget<TextField>(field('Concepto')).controller!.text,
      'Sin guardar',
    );
    await tap(t, 'Cancelar');
    await tap(t, 'Descartar cambios');
    expect(find.text('Concepto: Café sintético'), findsOneWidget);
    expect(
      (await io(t, () => source.management.get(old.id))).data.concept,
      old.data.concept,
    );
  });
  testWidgets(
    'Fecha fuera de vigencia explica cuentas elegibles; no crea datos',
    (t) async {
      await mount(t);
      await enter(t, 'Fecha de valor · AAAA-MM-DD', '2026-05-01');
      expect(
        find.textContaining('No hay cuentas corrientes vigentes'),
        findsOneWidget,
      );
      expect(find.textContaining('Cartera excluida'), findsNothing);
      await enter(t, 'Concepto', 'Sin cuenta');
      await enter(t, 'Importe firmado (EUR)', '1');
      await tap(t, 'Guardar movimiento');
      expect(saved, isNull);
      expect(
        find.text('Elige una cuenta vigente para esta fecha.'),
        findsOneWidget,
      );
      expect(
        (await io(
          t,
          () => createMovementListSource(
            db,
            invalidation,
          ).movements.readMonth(2026, 5),
        )),
        isEmpty,
      );
    },
  );
  testWidgets('Cuenta histórica se muestra sin elegibilidad al cambiar fecha', (
    t,
  ) async {
    final old = await io(t, existing);
    await mount(t, id: old.id);
    await tap(t, 'Editar');
    await enter(t, 'Fecha de valor · AAAA-MM-DD', '2026-05-01');
    expect(
      find.textContaining('Referencia histórica no elegible'),
      findsOneWidget,
    );
    await tap(t, 'Guardar movimiento');
    expect(saved, isNull);
    expect(
      (await io(t, () => source.management.get(old.id))).data.valueDate.value,
      '2026-03-15',
    );
  });
  testWidgets('Cierre solicita confirmación conservadora y no escribe', (
    t,
  ) async {
    await mount(t);
    await enter(t, 'Concepto', 'Borrador al cerrar');
    final response = t.binding.handleRequestAppExit();
    await settle(t);
    expect(find.text('Hay cambios sin guardar'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(t);
    expect(await response, AppExitResponse.cancel);
    expect(
      t.widget<TextField>(field('Concepto')).controller!.text,
      'Borrador al cerrar',
    );
    final discard = t.binding.handleRequestAppExit();
    await settle(t);
    await tap(t, 'Descartar cambios');
    expect(await discard, AppExitResponse.exit);
    expect(saved, isNull);
  });
  testWidgets(
    'Revalidación SQLite rechaza categoría archivada después de elegir sin perder campos',
    (t) async {
      final old = await io(
        t,
        () => source.management.create(
          accountId: account,
          valueDate: '2026-03-12',
          concept: 'Sin categoría',
          amount: '-2',
        ),
      );
      final option = (await io(t, source.categories)).single;
      await mount(t, id: old.id, pick: (_) async => option);
      await tap(t, 'Editar');
      await enter(t, 'Concepto', 'Borrador conservado');
      await tap(t, 'Seleccionar categoría');
      await io(
        t,
        () =>
            SqliteCategoryRepository(db).setArchived(category, archived: true),
      );
      await tap(t, 'Guardar movimiento');
      expect(saved, isNull);
      expect(
        find.text('La categoría no existe o está archivada.'),
        findsOneWidget,
      );
      final unchanged = await io(t, () => source.management.get(old.id));
      expect(unchanged.data.categoryId, isNull);
      expect(unchanged.data.concept, 'Sin categoría');
      expect(
        t.widget<TextField>(field('Concepto')).controller!.text,
        'Borrador conservado',
      );
      await io(
        t,
        () =>
            SqliteCategoryRepository(db).setArchived(category, archived: false),
      );
      await tap(t, 'Guardar movimiento');
      expect(saved!.data.categoryId, category);
    },
  );
  testWidgets('Detalle importado y edición conservan fila, lote e identidad', (
    t,
  ) async {
    await io(
      t,
      () => SqliteImportBatchRepository(db).create(
        sha256: 'b' * 64,
        source: ImportSource.historicalCsv,
        originalName: 'fixture-sintetico.csv',
        contractVersion: '1',
        movements: [
          ImportedMovement(
            2,
            MovementInput(
              accountId: account,
              valueDate: ValueDate(2026, 3, 15),
              concept: 'Importado sintético',
              amountCents: -1250,
              categoryId: category,
              discretion: 'original',
            ),
          ),
        ],
      ),
    );
    final old = (await io(
      t,
      () => createMovementListSource(
        db,
        invalidation,
      ).movements.readMonth(2026, 3),
    )).single;
    await mount(t, id: old.id);
    expect(
      find.textContaining('Procedencia: ${old.importRowId}'),
      findsOneWidget,
    );
    expect(find.textContaining('Fila: 2'), findsOneWidget);
    await tap(t, 'Editar');
    await enter(t, 'Discrecionalidad opcional', 'editada');
    await tap(t, 'Guardar movimiento');
    expect(saved!.importRowId, old.importRowId);
    expect(saved!.batchId, old.batchId);
    expect(saved!.sourceOrdinal, 2);
    expect(saved!.id, old.id);
    expect(saved!.data.discretion, 'editada');
    expect(saved!.data.amountCents, -1250);
  });
  testWidgets(
    'Rutas inválidas o entidad ausente no escriben y permiten volver',
    (t) async {
      final before = (await io(t, db.readState)).revision;
      for (final path in [
        '/movimientos/no-uuid',
        '/movimientos/nuevo?a=bad&m=03',
        '/movimientos/nuevo/extra',
        '/movimientos/00000000-0000-0000-0000-000000000000',
      ]) {
        await t.pumpWidget(
          MaterialApp(
            key: ValueKey(path),
            initialRoute: path,
            onGenerateRoute: (settings) => AppRouter.generateRoute(
              settings,
              movements: () async => createMovementListSource(db, invalidation),
            ),
          ),
        );
        await settle(t);
        expect(
          find.textContaining('No se pudo abrir este detalle'),
          findsOneWidget,
        );
        expect(find.textContaining('Volver'), findsWidgets);
      }
      expect((await io(t, db.readState)).revision, before);
    },
  );
  testWidgets(
    'Lista → editor → guardado fuera de mes devuelve contexto y Ver mes',
    (t) async {
      final old = await io(t, existing);
      await t.pumpWidget(
        MaterialApp(
          initialRoute: '/movimientos?a=2026&m=03',
          onGenerateRoute: (settings) => AppRouter.generateRoute(
            settings,
            movements: () async => createMovementListSource(db, invalidation),
            categories: () async => createCategoryManagement(
              database: db,
              invalidation: invalidation,
            ),
          ),
        ),
      );
      await settle(t);
      await tap(t, 'Abrir Café sintético');
      await tap(t, 'Editar');
      await enter(t, 'Fecha de valor · AAAA-MM-DD', '2026-04-02');
      await tap(t, 'Guardar movimiento');
      expect(find.textContaining('Periodo 2026-03-01'), findsOneWidget);
      expect(find.text('Movimiento guardado en 2026-04'), findsOneWidget);
      expect(find.text('Abrir Café sintético'), findsNothing);
      await tap(t, 'Ver mes');
      expect(find.textContaining('Periodo 2026-04-01'), findsOneWidget);
      expect(find.text('Abrir Café sintético'), findsOneWidget);
      expect(
        (await io(t, () => source.management.get(old.id))).data.valueDate.value,
        '2026-04-02',
      );
    },
  );
  for (final width in [320.0, 412.0, 1024.0, 1440.0]) {
    testWidgets('Formulario a $width px con texto 200 %', (t) async {
      t.view.physicalSize = Size(width, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: MovementFormScreen(
            load: () async => source,
            initialDate: ValueDate(2026, 3, 1),
            onReturn: () {},
            onSaved: (_) {},
            onDeleted: () {},
            selectCategory: (_) async => null,
            destinations: {
              for (final name in [
                'Estado',
                'Patrimonio',
                'Presupuesto',
                'Real',
                'Indicadores',
              ])
                name: () {},
            },
          ),
        ),
      );
      await settle(t);
      await enter(t, 'Concepto', 'Borrador');
      await tap(t, 'Cancelar');
      expect(find.text('Hay cambios sin guardar'), findsOneWidget);
      await tap(t, 'Seguir editando');
      expect(t.takeException(), isNull);
    });
  }
}
