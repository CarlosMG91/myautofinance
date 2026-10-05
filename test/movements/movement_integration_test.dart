import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/local_backup_session.dart';
import 'package:myautofinance/app/movement_list_factory.dart';
import 'package:myautofinance/app/navigation/movement_links.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/movements/presentation/category_selector.dart';
import 'package:myautofinance/features/movements/presentation/movement_form_screen.dart';
import 'package:myautofinance/features/movements/presentation/movement_list_controller.dart';
import 'package:myautofinance/features/movements/presentation/movement_list_screen.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  late LocalDatabase db;
  late CategoryReadInvalidation invalidation;
  late MovementListController controller;
  late String root, target, account;
  late List<String> ids;

  Future<void> seed(LocalDatabase database) async {
    account = (await SqliteAccountRepository(database).create(
      name: 'Cuenta sintética',
      kind: AccountKind.account,
      activeFrom: Month(2026, 1),
      liquidity: Liquidity.liquid,
    )).id;
    root = (await SqliteCategoryRepository(database).create(name: 'Ocio')).id;
    target = (await SqliteCategoryRepository(database).create(name: 'Destino'))
        .id;
    ids = [];
    for (var i = 0; i < 3; i++) {
      ids.add(
        (await SqliteMovementRepository(database).create(
          MovementInput(
            accountId: account,
            valueDate: ValueDate(2026, 3, i + 1),
            concept: 'Café sintético $i',
            amountCents: i == 0 ? 1000 : -200,
            categoryId: root,
            discretion: 'Texto conservado $i',
          ),
        )).id,
      );
    }
  }

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
    invalidation = CategoryReadInvalidation();
    await seed(db);
    controller = MovementListController(
      load: () async => createMovementListSource(db, invalidation),
      from: ValueDate(2026, 3, 1),
      until: ValueDate(2026, 4, 1),
      pageSize: 2,
    );
  });
  tearDown(() async {
    await invalidation.close();
    await db.close();
  });

  Future<List<Map<String, Object?>>> rows() async =>
      (await db.customSelect('SELECT * FROM movements ORDER BY id').get())
          .map((r) => r.data)
          .toList();
  Future<int> revision() async => (await db.readState()).revision;

  test(
    'Página capturada: conserva ocultos/campos y refresca subtotal y selección',
    () async {
      await controller.refresh();
      expect(controller.page!.subtotalCents, 600);
      controller.selectPage();
      final before = await rows();
      final previousRevision = await revision();
      final request = controller.beginBatch()!;
      expect(request.selection.ids.toSet(), {ids[1], ids[2]});
      controller.toggle(ids[0], true);
      expect(controller.selected, {ids[1], ids[2]});
      await controller.executeBatch(
        request,
        MovementBatchAction.assignCategory,
        categoryId: target,
      );
      expect(controller.notice, '2 movimientos categorizados.');
      expect(await revision(), previousRevision + 1);
      expect(controller.selected, {ids[1], ids[2]});
      final after = await rows();
      for (var i = 0; i < before.length; i++) {
        final id = before[i]['id'];
        expect(after[i]['category_id'], id == ids[0] ? root : target);
        expect(
          {...after[i]}
            ..remove('category_id')
            ..remove('updated_at'),
          {...before[i]}
            ..remove('category_id')
            ..remove('updated_at'),
        );
      }
      final remove = controller.beginBatch()!;
      await controller.executeBatch(remove, MovementBatchAction.removeCategory);
      expect(controller.notice, '2 movimientos sin categoría.');
      expect(
        (await SqliteMovementRepository(db).get(ids[0]))!.data.categoryId,
        root,
      );
      final deleting = controller.beginBatch()!;
      await controller.executeBatch(deleting, MovementBatchAction.delete);
      expect(controller.selected, isEmpty);
      expect(controller.page!.records.single.id, ids[0]);
      expect(controller.page!.subtotalCents, 1000);
      expect(controller.notice, '2 movimientos borrados.');
      controller.dispose();
    },
  );

  test(
    'Cambiar de categoría sale del filtro y recalcula su subtotal firmado',
    () async {
      controller.categoryId = root;
      await controller.refresh();
      controller.toggle(ids[2], true);
      await controller.executeBatch(
        controller.beginBatch()!,
        MovementBatchAction.assignCategory,
        categoryId: target,
      );
      expect(controller.page!.subtotalCents, 800);
      expect(controller.page!.records.map((r) => r.id), [ids[1], ids[0]]);
      expect(controller.selected, isEmpty);
      expect(controller.categoryId, root);
      controller.dispose();
    },
  );

  for (final action in MovementBatchAction.values) {
    test(
      'Rechazo de $action: rollback, sin éxito anunciado y selección intacta',
      () async {
        await controller.refresh();
        controller.selectPage();
        final snapshot = await rows();
        final previousRevision = await revision();
        final event = action == MovementBatchAction.delete
            ? 'DELETE'
            : 'UPDATE';
        await db.customStatement('''
        CREATE TRIGGER reject_selected BEFORE $event ON movements
        WHEN OLD.id = '${ids[1]}'
        BEGIN SELECT RAISE(ABORT,'synthetic failure'); END
      ''');
        await controller.executeBatch(
          controller.beginBatch()!,
          action,
          categoryId: target,
        );
        expect(await rows(), snapshot);
        expect(await revision(), previousRevision);
        expect(controller.selected, {ids[1], ids[2]});
        expect(controller.notice, isNull);
        expect(controller.error, contains('Lote rechazado'));
        expect(controller.batchActive, isFalse);
        controller.dispose();
      },
    );
  }

  test(
    'UUID desaparecido rechaza completo; relectura descarta solo el ID ausente',
    () async {
      await controller.refresh();
      controller.selectPage();
      final request = controller.beginBatch()!;
      await SqliteMovementRepository(db).delete(ids[1]);
      final before = await rows();
      final previousRevision = await revision();
      await controller.executeBatch(
        request,
        MovementBatchAction.removeCategory,
      );
      expect(controller.selected, {ids[1], ids[2]});
      expect(await rows(), before);
      expect(await revision(), previousRevision);
      await controller.refresh();
      expect(controller.selected, {ids[2]});
      controller.dispose();
    },
  );

  test('Categoría archivada tras selector rechaza sin ampliar ni perder la selección', () async {
    await controller.refresh();
    controller.toggle(ids[2], true);
    final request = controller.beginBatch()!;
    await SqliteCategoryRepository(db).setArchived(target, archived: true);
    final previousRevision = await revision();
    await controller.executeBatch(
      request,
      MovementBatchAction.assignCategory,
      categoryId: target,
    );
    expect(controller.selected, {ids[2]});
    expect(controller.error, contains('Lote rechazado'));
    expect(await revision(), previousRevision);
    expect(
      (await SqliteMovementRepository(db).get(ids[2]))!.data.categoryId,
      root,
    );
    controller.dispose();
  });

  test(
    'Restaurar la misma copia y revisión invalida la selección capturada',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'movement-094-synthetic-',
      );
      final session = LocalBackupSession(
        supportDirectory: () async => directory,
      );
      try {
        expect(await session.open(), isTrue);
        final original = await session.store.open();
        await seed(original);
        await session.controller.create();
        expect(session.controller.error, isNull);
        final backup = session.controller.listing!.entries.single.backupId;
        final list = MovementListController(
          load: session.movements,
          from: ValueDate(2026, 3, 1),
          until: ValueDate(2026, 4, 1),
          pageSize: 2,
        );
        try {
          await list.refresh();
          await list.next();
          expect(list.pageIndex, 1);
          list.selectPage();
          final request = list.beginBatch()!;
          final before = await original.readState();
          await session.controller.restore(backup, confirmed: true);
          expect(session.controller.error, isNull);
          final restored = await session.store.open();
          final state = await restored.readState();
          expect(state.datasetId, before.datasetId);
          expect(state.revision, before.revision);
          expect(restored, isNot(same(original)));
          await list.executeBatch(request, MovementBatchAction.delete);
          expect(list.error, contains('se ha sustituido'));
          expect(list.selected, request.selection.ids.toSet());
          expect((await restored.readState()).revision, state.revision);
          expect(
            await SqliteMovementRepository(restored).get(ids[0]),
            isNotNull,
          );
          await list.refresh();
          expect(list.selected, isEmpty);
          expect(list.pageIndex, 0);
          expect(list.page!.records.map((r) => r.id), [ids[2], ids[1]]);
          list.selectPage();
          await list.executeBatch(
            list.beginBatch()!,
            MovementBatchAction.removeCategory,
          );
          expect(list.error, isNull);
          expect(list.notice, '2 movimientos sin categoría.');
        } finally {
          list.dispose();
        }
      } finally {
        await session.store.close();
        session.controller.dispose();
        await session.categoryInvalidation.close();
        await directory.delete(recursive: true);
      }
      controller.dispose();
    },
  );

  test(
    'La espera de escritura bloquea doble envío y no anuncia un éxito previo',
    () async {
      await controller.refresh();
      controller.selectPage();
      final pending = Completer<MovementListSource>();
      var waiting = false;
      final source = createMovementListSource(db, invalidation);
      final list = MovementListController(
        load: () => waiting ? pending.future : Future.value(source),
        from: controller.from,
        until: controller.until,
      );
      await list.refresh();
      list.toggle(ids[2], true);
      waiting = true;
      final request = list.beginBatch()!;
      final writing = list.executeBatch(request, MovementBatchAction.delete);
      expect(list.batchActive, isTrue);
      expect(list.beginBatch(), isNull);
      expect(list.notice, isNull);
      expect(await source.movements.get(ids[2]), isNotNull);
      waiting = false;
      pending.complete(source);
      await writing;
      expect(list.notice, '1 movimiento borrado.');
      expect(list.selected, isEmpty);
      expect(await source.movements.get(ids[2]), isNull);
      list.dispose();
      controller.dispose();
    },
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final finder = find.text(label).last;
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await settle(tester);
  }

  Future<NavigatorState> mount(WidgetTester tester, {String? route}) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AutofinanceApp(
        movements: () async => createMovementListSource(db, invalidation),
        categories: () async =>
            createCategoryManagement(database: db, invalidation: invalidation),
      ),
    );
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.pushNamed(route ?? '/movimientos?a=2026&m=03');
    await settle(tester);
    return nav;
  }

  testWidgets(
    'Selector compartido: cancelación intacta, confirmación y commit visibles',
    (tester) async {
      await mount(tester);
      final list = tester
          .widget<MovementListScreen>(find.byType(MovementListScreen))
          .controller;
      list.toggle(ids[2], true);
      await tester.pump();
      final before = await tester.runAsync(rows);
      await tap(tester, 'Asignar categoría');
      expect(find.byType(CategorySelector), findsOneWidget);
      await tap(tester, 'Cancelar');
      expect(list.selected, {ids[2]});
      expect(await tester.runAsync(rows), before);
      await tap(tester, 'Asignar categoría');
      await tap(tester, 'Destino');
      await tap(tester, 'Seleccionar');
      expect(find.text('Asignar categoría a 1 movimiento'), findsOneWidget);
      expect(await tester.runAsync(rows), before);
      await tap(tester, 'Cancelar');
      expect(list.selected, {ids[2]});
      await tap(tester, 'Asignar categoría');
      await tap(tester, 'Destino');
      await tap(tester, 'Seleccionar');
      await tap(tester, 'Asignar categoría');
      expect(find.text('1 movimiento categorizado.'), findsOneWidget);
      expect(
        (await tester.runAsync(() => SqliteMovementRepository(db).get(ids[2])))!
            .data
            .categoryId,
        target,
      );
      await tap(tester, 'Quitar categoría');
      expect(find.text('1 movimiento sin categoría.'), findsOneWidget);
      expect(list.selected, {ids[2]});
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  for (final width in [320.0, 412.0, 1440.0]) {
    testWidgets(
      'Borrar lote a $width px/200%: Esc y Atrás cancelan, éxito limpia IDs',
      (tester) async {
        final nav = await mount(tester);
        tester.view.physicalSize = Size(width, 1000);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        final list = tester
            .widget<MovementListScreen>(find.byType(MovementListScreen))
            .controller;
        list.toggle(ids[1], true);
        list.toggle(ids[2], true);
        await tester.pump();
        final before = await tester.runAsync(rows);
        await tap(tester, 'Borrar seleccionados (2)');
        expect(find.text('Borrar 2 movimientos'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester);
        expect(list.selected, {ids[1], ids[2]});
        expect(await tester.runAsync(rows), before);
        await tap(tester, 'Borrar seleccionados (2)');
        await nav.maybePop();
        await settle(tester);
        expect(list.selected, {ids[1], ids[2]});
        await tap(tester, 'Borrar seleccionados (2)');
        await tap(tester, 'Confirmar borrado');
        expect(find.text('2 movimientos borrados.'), findsOneWidget);
        expect(list.selected, isEmpty);
        expect(list.page!.subtotalCents, 1000);
        expect(list.page!.records.single.id, ids[0]);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }

  testWidgets(
    'Formulario leído antes de restaurar conserva borrador y rechaza escritura',
    (tester) async {
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('movement-editor-094-'),
      );
      final session = LocalBackupSession(
        supportDirectory: () async => directory!,
      );
      try {
        await tester.runAsync(() async {
          expect(await session.open(), isTrue);
          await seed(await session.store.open());
          await session.controller.create();
          expect(session.controller.error, isNull);
        });
        final backup = session.controller.listing!.entries.single.backupId;
        var saved = false;
        await tester.pumpWidget(
          MaterialApp(
            home: MovementFormScreen(
              load: () async => (await session.movements()).editor!(),
              initialDate: ValueDate(2026, 3, 1),
              id: ids[2],
              onReturn: () {},
              onSaved: (_) => saved = true,
              onDeleted: () {},
              selectCategory: (_) async => null,
            ),
          ),
        );
        await settle(tester);
        await tap(tester, 'Editar');
        final concept = find.widgetWithText(TextField, 'Concepto');
        await tester.ensureVisible(concept);
        await tester.enterText(concept, 'Borrador conservado');
        await tester.runAsync(
          () => session.controller.restore(backup, confirmed: true),
        );
        expect(session.controller.error, isNull);
        await tap(tester, 'Guardar movimiento');
        expect(saved, isFalse);
        expect(
          find.textContaining('La base local se ha sustituido.'),
          findsOneWidget,
        );
        expect(
          tester.widget<TextField>(concept).controller!.text,
          'Borrador conservado',
        );
        final record = await tester.runAsync(
          () async =>
              SqliteMovementRepository(await session.store.open()).get(ids[2]),
        );
        expect(record!.data.concept, 'Café sintético 2');
        await tester.pumpWidget(const SizedBox());
      } finally {
        await tester.runAsync(() async {
          await session.store.close();
          session.controller.dispose();
          await session.categoryInvalidation.close();
          await directory!.delete(recursive: true);
        });
      }
      controller.dispose();
    },
  );

  testWidgets(
    'Gestión mantiene mes y entradas previas; informe mantiene filtros/origen al volver',
    (tester) async {
      final origin = '/real?a=2026&m=03&rama=$root&alcance=directo';
      final nav = await mount(tester, route: origin);
      await tap(tester, 'Gestión');
      for (final label in [
        'Categorías',
        'Fichas',
        'Copia en Drive',
        'Copias locales',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tap(tester, 'Movimientos');
      final list = tester
          .widget<MovementListScreen>(find.byType(MovementListScreen))
          .controller;
      expect(list.from.value, '2026-03-01');
      expect(list.categoryId, isNull);
      expect(list.page!.records.first.id, ids[2]);
      nav.pop();
      await settle(tester);
      final query = MovementListQuery(
        from: ValueDate(2026, 3, 2),
        until: ValueDate(2026, 4, 1),
        categoryId: root,
        scope: MovementCategoryScope.direct,
        accountId: account,
        concept: 'CAFE',
      );
      nav.pushNamed(MovementLinks.list(query, origin: origin));
      await settle(tester);
      final reportList = tester
          .widget<MovementListScreen>(find.byType(MovementListScreen))
          .controller;
      expect(reportList.from.value, query.from.value);
      expect(reportList.scope, MovementCategoryScope.direct);
      expect(reportList.categoryId, root);
      expect(reportList.accountId, account);
      expect(reportList.concept, 'CAFE');
      reportList.toggle(ids[2], true);
      await tester.pump();
      await tap(tester, 'Abrir Café sintético 2');
      expect(find.byType(MovementFormScreen), findsOneWidget);
      await tap(tester, 'Volver a Movimientos');
      expect(reportList.selected, {ids[2]});
      expect(reportList.from.value, query.from.value);
      nav.pop();
      await settle(tester);
      expect(
        ModalRoute.of(tester.element(find.text('Real anual')))?.settings.name,
        origin,
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
