import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/import_factory.dart';
import 'package:myautofinance/app/wealth_management_factory.dart';
import 'package:myautofinance/app/budget_factory.dart';
import 'package:myautofinance/features/importing/presentation/import_history_screen.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/movement_list_factory.dart';
import 'package:myautofinance/app/navigation/app_routes.dart';
import 'package:myautofinance/app/pending_movement_factory.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/movements/presentation/pending_movement_controller.dart';
import 'package:myautofinance/features/movements/presentation/pending_movement_screen.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (const bool.fromEnvironment('CAPTURE_PENDING')) {
      final bytes = ByteData.sublistView(
        await File('C:/Windows/Fonts/segoeui.ttf').readAsBytes(),
      );
      for (final family in ['Roboto', 'Segoe UI']) {
        await (FontLoader(family)..addFont(Future.value(bytes))).load();
      }
      final icons = ByteData.sublistView(
        await File(
          '.tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
        ).readAsBytes(),
      );
      await (FontLoader('MaterialIcons')..addFont(Future.value(icons))).load();
    }
  });
  late LocalDatabase db;
  late LocalDatabase activeDb;
  late CategoryReadInvalidation invalidation;
  late PendingMovementController c;
  late SqliteMovementRepository repo;
  late String account, batch, root, child, leaf, manual;
  var failRead = false;
  Completer<void>? gate;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
    activeDb = db;
    invalidation = CategoryReadInvalidation();
    repo = SqliteMovementRepository(db);
    account = (await SqliteAccountRepository(db).create(
      name: 'Cuenta sintética',
      kind: AccountKind.account,
      activeFrom: Month(1, 1),
      liquidity: Liquidity.liquid,
    )).id;
    final categories = SqliteCategoryRepository(db);
    root = (await categories.create(name: 'Duplicada')).id;
    child = (await categories.create(name: 'Duplicada', parentId: root)).id;
    leaf = (await categories.create(name: 'Duplicada', parentId: child)).id;
    MovementInput input(String date, String concept, {String? category}) =>
        MovementInput(
          accountId: account,
          valueDate: ValueDate.parse(date),
          concept: concept,
          amountCents: -320,
          categoryId: category,
          discretion: 'Sintético',
        );
    batch = (await SqliteImportBatchRepository(db).create(
      sha256: 'a' * 64,
      source: ImportSource.historicalCsv,
      originalName: 'sintetico.csv',
      contractVersion: '1',
      movements: [
        ImportedMovement(2, input('2026-10-25', 'CAFÉ')),
        ImportedMovement(3, input('2026-10-25', 'CAFÉ')),
        ImportedMovement(4, input('0001-01-01', 'Antiguo')),
        ImportedMovement(5, input('9999-12-31', 'Futuro')),
        ImportedMovement(
          6,
          input('2026-01-01', 'Ya categorizado', category: root),
        ),
      ],
    )).id;
    manual = (await repo.create(input('2026-10-25', 'Manual'))).id;
    failRead = false;
    gate = null;
    c = PendingMovementController(
      pageSize: 2,
      load: () async {
        await gate?.future;
        if (failRead) throw StateError('Fallo sintético de lectura');
        return createPendingMovementSource(activeDb, invalidation);
      },
    );
  });

  tearDown(() async {
    await invalidation.close();
    await db.close();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<CategoryDetails> category() => createCategoryManagement(
    database: db,
    invalidation: invalidation,
  ).get(leaf);

  test(
    'Todos los periodos, total SQL, UUID visibles, filtros y página',
    () async {
      await c.refresh();
      expect(c.page!.totalCount, 4);
      expect(c.page!.records.first.data.valueDate.value, '9999-12-31');
      expect(c.page!.records.any((r) => r.id == manual), isFalse);
      c.toggle(manual, true);
      expect(c.selected, isEmpty);
      c.selectPage();
      expect(c.selected, hasLength(2));
      await c.next();
      expect(c.selected, isEmpty);
      expect(c.page!.totalCount, 4);
      c.selectPage();
      c.filtersEdited();
      expect(c.selected, isEmpty);
      expect(c.canAssign, isFalse);
      await c.apply(
        PendingMovementQuery(
          batchId: batch,
          accountId: account,
          concept: 'cafe',
        ),
      );
      expect(c.pageIndex, 0);
      expect(c.page!.totalCount, 2);
      expect(c.page!.records.every((r) => r.data.concept == 'CAFÉ'), isTrue);
      c.dispose();
    },
  );

  test('Cancelación conserva selección; éxito persistido reinicia páginas con filtros', () async {
    await c.apply(PendingMovementQuery(batchId: batch));
    await c.next();
    c.selectPage();
    final ids = c.selected.toList();
    final revision = (await db.readState()).revision;
    c.beginAssignment();
    c.cancelAssignment();
    expect(c.selected.toList(), ids);
    expect((await db.readState()).revision, revision);
    final request = c.beginAssignment()!;
    expect(await c.assign(request, leaf), isTrue);
    expect(c.page!.totalCount, 2);
    expect(c.pageIndex, 0);
    expect(c.query.batchId, batch);
    expect(c.selected, isEmpty);
    expect((await db.readState()).revision, revision + 1);
    for (final id in ids) {
      expect((await repo.get(id))!.data.categoryId, leaf);
    }
    expect((await repo.get(manual))!.data.categoryId, isNull);
    c.dispose();
  });

  for (final conflict in ['category', 'deleted', 'archived']) {
    test(
      'Obsolescencia $conflict: rollback, selección conservada y actualización obligatoria',
      () async {
        await c.refresh();
        c.selectPage();
        final ids = c.selected.toList();
        final request = c.beginAssignment()!;
        switch (conflict) {
          case 'category':
            await repo.setCategoryBatch([ids.first], root);
          case 'deleted':
            await repo.delete(ids.first);
          case 'archived':
            await SqliteCategoryRepository(db)
                .setArchived(root, archived: true);
        }
        final revision = (await db.readState()).revision;
        expect(await c.assign(request, leaf), isFalse);
        expect(c.selected.toList(), ids);
        expect(c.requiresRefresh, isTrue);
        expect(c.beginAssignment(), isNull);
        expect((await repo.get(ids.last))!.data.categoryId, isNull);
        expect((await db.readState()).revision, revision);
        await c.update();
        expect(c.requiresRefresh, isFalse);
        expect(c.selected, isEmpty);
        expect(c.beginAssignment(), isNull);
        c.dispose();
      },
    );
  }

  test(
    'Fallo de escritura permite reintentar, sin éxito ni selección perdida',
    () async {
      await c.refresh();
      c.selectPage();
      final ids = c.selected.toList();
      await db.customStatement(
        'CREATE TEMP TRIGGER fail_pending BEFORE UPDATE OF category_id ON movements BEGIN SELECT RAISE(ABORT,\'synthetic\'); END',
      );
      final revision = (await db.readState()).revision;
      expect(await c.assign(c.beginAssignment()!, leaf), isFalse);
      expect(c.requiresRefresh, isFalse);
      expect(c.selected.toList(), ids);
      expect((await db.readState()).revision, revision);
      await db.customStatement('DROP TRIGGER fail_pending');
      expect(await c.assign(c.beginAssignment()!, leaf), isTrue);
      expect(c.selected, isEmpty);
      c.dispose();
    },
  );

  test(
    'Doble envío bloqueado hasta persistencia y sin aviso de éxito anticipado',
    () async {
      await c.refresh();
      c.selectPage();
      final request = c.beginAssignment()!;
      gate = Completer<void>();
      final first = c.assign(request, leaf);
      expect(c.sending, isTrue);
      expect(c.notice, isNull);
      expect(await c.assign(request, leaf), isFalse);
      expect(c.selected, hasLength(2));
      gate!.complete();
      expect(await first, isTrue);
      expect(c.selected, isEmpty);
      c.dispose();
    },
  );

  test(
    'Error de lectura conserva filtros/UUID y no inventa contador',
    () async {
      await c.refresh();
      c.selectPage();
      failRead = true;
      await c.refresh();
      expect(c.page, isNull);
      expect(c.selected, hasLength(2));
      expect(c.beginAssignment(), isNull);
      failRead = false;
      await c.refresh();
      expect(c.selected, hasLength(2));
      expect(c.page!.totalCount, 4);
      c.dispose();
    },
  );

  test(
    'Sustituir conexión durante confirmación exige releer y reseleccionar',
    () async {
      await c.refresh();
      c.selectPage();
      final request = c.beginAssignment()!;
      final ids = c.selected.toList();
      final replacement = LocalDatabase(
        NativeDatabase.memory(setup: configureConnection),
      );
      addTearDown(replacement.close);
      activeDb = replacement;
      expect(await c.assign(request, leaf), isFalse);
      expect(c.selected.toList(), ids);
      expect(c.requiresRefresh, isTrue);
      expect(c.beginAssignment(), isNull);
      await c.update();
      expect(c.selected, isEmpty);
      expect(c.page!.totalCount, 0);
      for (final id in ids) {
        expect((await repo.get(id))!.data.categoryId, isNull);
      }
      c.dispose();
    },
  );

  testWidgets('Conflicto visible bloquea reenvío; actualizar limpia UUID', (
    tester,
  ) async {
    final destination = (await tester.runAsync(category))!;
    await tester.pumpWidget(
      MaterialApp(
        home: PendingMovementScreen(
          controller: c,
          onReturn: () {},
          onOpen: (_) async {},
          selectCategory: () async => destination,
        ),
      ),
    );
    await settle(tester);
    c.selectPage();
    await tester.pump();
    await tester.ensureVisible(find.text('Asignar categoría (2)'));
    await tester.tap(find.text('Asignar categoría (2)'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => repo.setCategoryBatch([c.selected.first], root),
    );
    await tester.tap(find.text('Guardar categoría'));
    await settle(tester);
    expect(c.requiresRefresh, isTrue);
    expect(c.selected, hasLength(2));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Asignar categoría (2)'),
          )
          .onPressed,
      isNull,
    );
    await tester.ensureVisible(find.text('Actualizar pendientes'));
    await tester.tap(find.text('Actualizar pendientes'));
    await settle(tester);
    expect(c.selected, isEmpty);
    expect(c.page!.totalCount, 3);
    expect(tester.takeException(), isNull);
  });

  for (final (width, scale) in [
    (320.0, 1.0),
    (360.0, 1.0),
    (412.0, 1.0),
    (839.0, 1.0),
    (840.0, 1.0),
    (1024.0, 1.0),
    (1440.0, 1.0),
    (320.0, 2.0),
    (412.0, 2.0),
    (1440.0, 2.0),
  ]) {
    testWidgets('Tabla/tarjetas, foco y confirmación $width × $scale', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final destination = (await tester.runAsync(category))!;
      final captureKey = GlobalKey();
      var selectorCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: RepaintBoundary(
            key: captureKey,
            child: PendingMovementScreen(
              controller: c,
              onReturn: () {},
              onOpen: (_) async {},
              selectCategory: () async {
                selectorCalls++;
                return destination;
              },
            ),
          ),
        ),
      );
      await settle(tester);
      expect(
        find.byType(Table),
        width >= 840 && scale == 1 ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Total pendiente del ámbito filtrado: 4 movimientos'),
        findsOneWidget,
      );
      expect(find.textContaining('Ya categorizado'), findsNothing);
      expect(find.textContaining('Manual\n'), findsNothing);
      await tester.ensureVisible(find.text('Seleccionar página visible (2)'));
      await tester.tap(find.text('Seleccionar página visible (2)'));
      await tester.pump();
      final chosen = c.selected.toList();
      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp('Seleccionar .* · ${chosen.first}')),
        findsOneWidget,
      );
      semantics.dispose();
      await tester.ensureVisible(find.text('Asignar categoría (2)'));
      await tester.tap(find.text('Asignar categoría (2)'));
      await tester.pumpAndSettle();
      expect(selectorCalls, 1);
      expect(find.textContaining(destination.path), findsOneWidget);
      expect(c.selected.toList(), chosen);
      expect(
        (await tester.runAsync(() => repo.get(chosen.first)))!.data.categoryId,
        isNull,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(c.selected.toList(), chosen);
      await tester.tap(find.text('Asignar categoría (2)'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Guardar categoría'));
      await tester.tap(find.text('Guardar categoría'));
      await settle(tester);
      expect(c.page!.totalCount, 2);
      expect(c.selected, isEmpty);
      expect(c.notice, contains('categorizados'));
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_PENDING') &&
          [
            (1440.0, 1.0),
            (412.0, 1.0),
            (412.0, 2.0),
          ].contains((width, scale))) {
        await tester.runAsync(() async {
          final boundary =
              captureKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final picture = await boundary.toImage();
          final data = await picture.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'docs/ep-015/flutter-${width.toInt()}-${scale.toInt()}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          picture.dispose();
        });
      }
    });
  }

  testWidgets('Filtros inclusivos/9999, invalidez y vacío útil', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PendingMovementScreen(
          controller: c,
          onReturn: () {},
          onOpen: (_) async {},
          selectCategory: () async => null,
        ),
      ),
    );
    await settle(tester);
    c.selectPage();
    await tester.pump();
    final from = find.widgetWithText(TextField, 'Desde · AAAA-MM-DD');
    final through = find.widgetWithText(
      TextField,
      'Hasta incluido · AAAA-MM-DD',
    );
    await tester.enterText(from, '2026-10-25');
    expect(c.selected, isEmpty);
    expect(c.canAssign, isFalse);
    await tester.enterText(through, '2026-10-25');
    await tester.ensureVisible(find.text('Aplicar filtros'));
    await tester.tap(find.text('Aplicar filtros'));
    await settle(tester);
    expect(c.page!.totalCount, 2);
    expect(c.query.until!.value, '2026-10-26');
    await tester.enterText(from, '9999-12-31');
    await tester.tap(find.text('Aplicar filtros'));
    await tester.pump();
    expect(c.filtersValid, isFalse);
    expect(c.beginAssignment(), isNull);
    expect(find.textContaining('Desde no puede'), findsOneWidget);
    await tester.enterText(through, '9999-12-31');
    await tester.tap(find.text('Aplicar filtros'));
    await settle(tester);
    expect(c.query.until, isNull);
    expect(c.page!.totalCount, 1);
    await tester.enterText(
      find.widgetWithText(TextField, 'Buscar por concepto'),
      'imposible',
    );
    await tester.tap(find.text('Aplicar filtros'));
    await settle(tester);
    expect(
      find.textContaining('No hay pendientes con estos filtros'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Ruta real: selector tres niveles, crear/cancelar y detalle EP-010',
    (tester) async {
      await tester.pumpWidget(
        AutofinanceApp(
          pendingMovements: () async =>
              createPendingMovementSource(db, invalidation),
          movements: () async => createMovementListSource(db, invalidation),
          categories: () async => createCategoryManagement(
            database: db,
            invalidation: invalidation,
          ),
        ),
      );
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pushNamed(AppRoutes.pendingMovements);
      await settle(tester);
      await tester.ensureVisible(find.text('Categorizar Futuro'));
      await tester.tap(find.text('Categorizar Futuro'));
      await settle(tester);
      expect(find.text('Duplicada'), findsOneWidget);
      expect(find.text('Duplicada / Duplicada'), findsOneWidget);
      expect(find.text('Duplicada / Duplicada / Duplicada'), findsOneWidget);
      await tester.tap(find.text('Duplicada / Duplicada / Duplicada'));
      await tester.pump();
      await tester.tap(find.text('Crear categoría'));
      await settle(tester);
      expect(find.text('Volver al selector'), findsOneWidget);
      await tester.ensureVisible(find.text('Cancelar'));
      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      expect(
        find.textContaining('Selección: Duplicada / Duplicada / Duplicada'),
        findsOneWidget,
      );
      await tester.tap(find.text('Seleccionar'));
      await tester.pumpAndSettle();
      expect(find.text('Confirmar asignación · 1 movimiento'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      await tester.ensureVisible(find.text('Abrir Futuro'));
      await tester.tap(find.text('Abrir Futuro'));
      await settle(tester);
      expect(find.text('Detalle de movimiento'), findsOneWidget);
      navigator.pop();
      await settle(tester);
      expect(find.text('Bandeja de categorización'), findsOneWidget);
      expect(
        find.text('Total pendiente del ámbito filtrado: 4 movimientos'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Categorizar Futuro'));
      await tester.tap(find.text('Categorizar Futuro'));
      await settle(tester);
      await tester.tap(find.text('Crear categoría'));
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre'),
        'Nueva sintética',
      );
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Crear categoría'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Crear categoría'));
      await settle(tester);
      expect(find.textContaining('Selección: Nueva sintética'), findsOneWidget);
      await tester.tap(find.text('Seleccionar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar categoría'));
      await settle(tester);
      expect(
        find.text('Total pendiente del ámbito filtrado: 3 movimientos'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  Future<NavigatorState> bootLinks(WidgetTester tester) async {
    await tester.pumpWidget(
      AutofinanceApp(
        pendingMovements: () async =>
            createPendingMovementSource(db, invalidation),
        imports: () async => createImportServices(db),
        wealth: () async => createWealthManagement(database: db),
        budgets: () async => createBudgetSource(db, invalidation),
        movements: () async => createMovementListSource(db, invalidation),
        categories: () async =>
            createCategoryManagement(database: db, invalidation: invalidation),
      ),
    );
    await settle(tester);
    return tester.state<NavigatorState>(find.byType(Navigator));
  }

  testWidgets('Gestión abre todos los periodos y vuelve al destino exacto', (
    tester,
  ) async {
    final nav = await bootLinks(tester);
    nav.pushNamed('${AppRoutes.actualSpending}?a=2020&m=2');
    await settle(tester);
    await tester.tap(find.text('Gestión'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pendientes de categorizar'));
    await settle(tester);
    expect(
      find.text('Total pendiente del ámbito filtrado: 4 movimientos'),
      findsOneWidget,
    );
    nav.pop();
    await settle(tester);
    expect(
      ModalRoute.of(tester.element(find.text('Real anual')))?.settings.name,
      '${AppRoutes.actualSpending}?a=2020&m=2',
    );
  });

  for (final width in [1440.0, 412.0]) {
    testWidgets(
      'Lote → bandeja → lote actualiza contador y conserva origen $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final nav = await bootLinks(tester);
        nav.pushNamed('${AppRoutes.importBatches}/$batch');
        await settle(tester);
        final originalState = tester.state(find.byType(ImportHistoryScreen));
        expect(find.text('Pendientes de categorizar: 4'), findsOneWidget);
        await tester.ensureVisible(find.text('Revisar pendientes del lote'));
        await tester.tap(find.text('Revisar pendientes del lote'));
        await settle(tester);
        expect(
          find.text('Total pendiente del ámbito filtrado: 4 movimientos'),
          findsOneWidget,
        );
        final screen = tester.widget<PendingMovementScreen>(
          find.byType(PendingMovementScreen),
        );
        expect(screen.controller.query.batchId, batch);
        screen.controller.selectPage();
        await tester.ensureVisible(find.text('Ver lote').first);
        await tester.tap(find.text('Ver lote').first);
        await settle(tester);
        expect(find.text('Detalle del lote'), findsOneWidget);
        nav.pop();
        await settle(tester);
        expect(screen.controller.query.batchId, batch);
        expect(screen.controller.selected, hasLength(4));
        final request = screen.controller.beginAssignment()!;
        await tester.runAsync(() => screen.controller.assign(request, leaf));
        await settle(tester);
        expect(
          find.text('Total pendiente del ámbito filtrado: 0 movimientos'),
          findsOneWidget,
        );
        nav.pop();
        await settle(tester);
        expect(
          tester.state(find.byType(ImportHistoryScreen)),
          same(originalState),
        );
        expect(find.text('Pendientes de categorizar: 0'), findsOneWidget);
        final button = tester.widget<TextButton>(
          find.widgetWithText(TextButton, 'Revisar pendientes del lote'),
        );
        expect(button.focusNode!.hasFocus, isTrue);
        await tester.tap(find.text('Revisar pendientes del lote'));
        await settle(tester);
        expect(find.textContaining('No hay pendientes'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Lote inexistente y parámetros inválidos no escriben', (
    tester,
  ) async {
    final nav = await bootLinks(tester);
    final before = (await db.readState()).revision;
    nav.pushNamed(
      '${AppRoutes.pendingMovements}?lote=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    );
    await settle(tester);
    expect(find.textContaining('Lote no encontrado.'), findsOneWidget);
    nav.pop();
    await settle(tester);
    for (final query in [
      'lote=no-uuid',
      'a=2026',
      'lote=$batch&lote=$batch',
      'lote=$batch#fragmento',
    ]) {
      nav.pushNamed('${AppRoutes.pendingMovements}?$query');
      await settle(tester);
      expect(find.text('No se pudo abrir la bandeja'), findsOneWidget);
      nav.pop();
      await settle(tester);
    }
    expect((await db.readState()).revision, before);
  });

  for (final path in [AppRoutes.wealth, AppRoutes.budget]) {
    testWidgets('Gestión de $path no impone periodo a pendientes', (
      tester,
    ) async {
      final nav = await bootLinks(tester);
      nav.pushNamed('$path?a=2020&m=02');
      await settle(tester);
      final origin = ModalRoute.of(tester.element(find.byTooltip('Gestión')));
      await tester.tap(find.byTooltip('Gestión'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pendientes de categorizar'));
      await settle(tester);
      expect(
        find.text('Total pendiente del ámbito filtrado: 4 movimientos'),
        findsOneWidget,
      );
      nav.pop();
      await settle(tester);
      expect(
        ModalRoute.of(tester.element(find.byTooltip('Gestión'))),
        same(origin),
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final (width, scale) in [(1440.0, 1.0), (412.0, 1.0), (412.0, 2.0)]) {
    testWidgets('Composición real con navegación $width × $scale', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: AutofinanceApp(
            pendingMovements: () async =>
                createPendingMovementSource(db, invalidation),
            movements: () async => createMovementListSource(db, invalidation),
            categories: () async => createCategoryManagement(
              database: db,
              invalidation: invalidation,
            ),
          ),
        ),
      );
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed(AppRoutes.pendingMovements);
      await settle(tester);
      expect(find.text('Estado'), findsOneWidget);
      expect(find.text('Indicadores'), findsOneWidget);
      expect(
        find.text('Total pendiente del ámbito filtrado: 4 movimientos'),
        findsOneWidget,
      );
      expect(
        find.byType(Table),
        width >= 840 && scale == 1 ? findsOneWidget : findsNothing,
      );
      await tester.ensureVisible(find.text('Seleccionar página visible (4)'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_PENDING')) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final picture = await boundary.toImage();
          final data = await picture.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'docs/ep-015/flutter-app-${width.toInt()}-${scale.toInt()}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          picture.dispose();
        });
      }
    });
  }
}
