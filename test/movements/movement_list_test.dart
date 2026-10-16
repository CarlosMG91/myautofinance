import 'dart:io';
import 'dart:async';

import '../support/drilldown_capture.dart';

import 'package:myautofinance/ui/autofinance_ui.dart';

import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/features/movements/movement_widgets.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/movement_list_factory.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/movements/presentation/movement_list_controller.dart';
import 'package:myautofinance/features/movements/presentation/movement_list_screen.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadDrilldownFonts();
    if (const bool.fromEnvironment('CAPTURE_MOVEMENT_LIST')) {
      final bytes = ByteData.sublistView(
        await File('C:/Windows/Fonts/segoeui.ttf').readAsBytes(),
      );
      for (final name in ['Segoe UI', 'Roboto']) {
        await (FontLoader(name)..addFont(Future.value(bytes))).load();
      }
    }
  });
  late LocalDatabase db;
  late CategoryReadInvalidation invalidation;
  late MovementListController controller;
  late String category;
  late List<String> ids;
  var fail = false;
  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
    invalidation = CategoryReadInvalidation();
    final account = await SqliteAccountRepository(db).create(
      name: 'Diaria',
      kind: AccountKind.account,
      activeFrom: Month(2026, 1),
      liquidity: Liquidity.liquid,
    );
    category = (await SqliteCategoryRepository(
      db,
    ).create(name: 'Ocio', isIncome: false)).id;
    final child = (await SqliteCategoryRepository(
      db,
    ).create(name: 'Café', parentId: category)).id;
    ids = [];
    for (var i = 0; i < 3; i++) {
      ids.add(
        (await SqliteMovementRepository(db).create(
          MovementInput(
            accountId: account.id,
            valueDate: ValueDate(2026, 3, i + 1),
            concept: i == 0 ? 'Árbol' : 'CAFÉ $i',
            amountCents: i == 0 ? 1000 : -200,
            categoryId: i == 0
                ? null
                : i == 1
                ? category
                : child,
          ),
        )).id,
      );
    }
    fail = false;
    controller = MovementListController(
      load: () async {
        if (fail) throw StateError('Lectura sintética rechazada');
        return createMovementListSource(db, invalidation);
      },
      from: ValueDate(2026, 3, 1),
      until: ValueDate(2026, 4, 1),
      pageSize: 2,
    );
  });
  tearDown(() async {
    await invalidation.close();
    await db.close();
  });
  test(
    'SQLite: selección exacta, subtotal global, filtros y recuperación',
    () async {
      await controller.refresh();
      expect(controller.page!.subtotalCents, 600);
      expect(controller.page!.totalCount, 3);
      expect(controller.page!.records.map((e) => e.id), [ids[2], ids[1]]);
      controller.selectPage();
      expect(controller.selection!.ids.toSet(), {ids[2], ids[1]});
      fail = true;
      await controller.refresh();
      expect(controller.page, isNull);
      expect(controller.selected.length, 2);
      fail = false;
      await controller.refresh();
      expect(controller.selected.length, 2);
      await controller.next();
      expect(controller.selected, isEmpty);
      expect(controller.page!.records.single.id, ids[0]);
      controller.concept = 'cafe';
      await controller.apply();
      expect(controller.page!.subtotalCents, -400);
      controller.categoryId = category;
      controller.scope = MovementCategoryScope.direct;
      await controller.apply();
      expect(controller.page!.records.single.id, ids[1]);
      controller.scope = MovementCategoryScope.branch;
      await controller.apply();
      expect(controller.page!.records.length, 2);
      final context = controller.context;
      controller.categoryId = null;
      controller.concept = '';
      controller.unclassified = true;
      await controller.apply();
      expect(controller.page!.records.single.id, ids[0]);
      expect(context.categoryId, category);
      controller.dispose();
    },
  );
  test('renombrar catálogo invalida rutas y conserva filtros', () async {
    await controller.refresh();
    controller.concept = 'cafe';
    await controller.apply();
    await SqliteCategoryRepository(db)
        .edit(category, name: 'Tiempo libre', parentId: null, isIncome: false);
    invalidation.invalidate();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(controller.paths[category], 'Tiempo libre');
    expect(controller.concept, 'cafe');
    controller.dispose();
  });
  test(
    'Reset recupera ámbito inicial y descarta cursor, selección y foco',
    () async {
      await controller.refresh();
      await controller.next();
      controller.selectPage();
      controller.concept = 'cafe';
      await controller.apply();
      expect(controller.reportFiltersChanged, isTrue);
      controller.scrollOffset = 400;
      controller.focus = ids[1];
      controller.selectPage();
      await controller.resetToReport();
      expect(controller.reportFiltersChanged, isFalse);
      expect(controller.pageIndex, 0);
      expect(controller.selected, isEmpty);
      expect(controller.scrollOffset, 0);
      expect(controller.focus, isNull);
      expect(controller.page!.totalCount, 3);
      expect(controller.page!.subtotalCents, 600);
      controller.dispose();
    },
  );
  test(
    'Respuesta tardía no reemplaza filtros ni subtotal del nuevo periodo',
    () async {
      final pending = Completer<MovementListSource>();
      var calls = 0;
      controller.dispose();
      controller = MovementListController(
        load: () => ++calls == 1
            ? pending.future
            : Future.value(createMovementListSource(db, invalidation)),
        from: ValueDate(2026, 3, 1),
        until: ValueDate(2026, 4, 1),
      );
      final old = controller.refresh();
      await controller.changePeriod(
        ValueDate(2026, 2, 1),
        ValueDate(2026, 3, 1),
      );
      expect(controller.page!.totalCount, 0);
      pending.complete(createMovementListSource(db, invalidation));
      await old;
      expect(controller.from.value, '2026-02-01');
      expect(controller.page!.totalCount, 0);
      expect(controller.page!.subtotalCents, 0);
      controller.dispose();
    },
  );
  test(
    'Restauración invalida selección antes de una lectura fallida',
    () async {
      controller.dispose();
      var restored = false;
      final identity = Object();
      controller = MovementListController(
        load: () async {
          final source = createMovementListSource(db, invalidation);
          return MovementListSource(
            movements: source.movements,
            categories: source.categories,
            accounts: restored
                ? () async => throw StateError('Fallo tras sustituir')
                : source.accounts,
            invalidation: invalidation,
            identity: restored ? identity : db,
            management: source.management,
          );
        },
        from: ValueDate(2026, 3, 1),
        until: ValueDate(2026, 4, 1),
        pageSize: 2,
      );
      await controller.refresh();
      await controller.next();
      controller.selectPage();
      expect(controller.selected, isNotEmpty);
      restored = true;
      await controller.refresh();
      expect(controller.error, isNotNull);
      expect(controller.page, isNull);
      expect(controller.selected, isEmpty);
      expect(controller.pageIndex, 0);
      expect(controller.beginBatch(), isNull);
      controller.dispose();
    },
  );
  test(
    'Una escritura invalida el cursor previo al volver del editor',
    () async {
      await controller.refresh();
      await controller.next();
      expect(controller.pageIndex, 1);
      await SqliteMovementRepository(db).delete(ids[0]);
      await controller.refresh();
      expect(controller.pageIndex, 0);
      expect(controller.page!.totalCount, 2);
      expect(controller.page!.records.map((r) => r.id), [ids[2], ids[1]]);
      controller.dispose();
    },
  );
  test(
    'Una escritura durante la lectura retira el resultado hasta reintentar',
    () async {
      controller.dispose();
      var mutate = true;
      controller = MovementListController(
        from: ValueDate(2026, 3, 1),
        until: ValueDate(2026, 4, 1),
        load: () async {
          final source = createMovementListSource(db, invalidation);
          return MovementListSource(
            movements: source.movements,
            categories: source.categories,
            accounts: () async {
              if (mutate) {
                mutate = false;
                await SqliteMovementRepository(db).delete(ids[0]);
              }
              return source.accounts();
            },
            invalidation: source.invalidation,
            identity: source.identity,
            management: source.management,
            readState: source.readState,
          );
        },
      );
      await controller.refresh();
      expect(controller.page, isNull);
      expect(controller.error, isNotNull);
      expect(controller.reportFiltersChanged, isFalse);
      await controller.refresh();
      expect(controller.error, isNull);
      expect(controller.page!.totalCount, 2);
      expect(controller.page!.subtotalCents, -400);
      controller.dispose();
    },
  );
  for (final (width, scale) in [
    (320.0, 1.0),
    (412.0, 1.0),
    (1024.0, 1.0),
    (1440.0, 1.0),
    (320.0, 2.0),
    (1440.0, 2.0),
  ]) {
    testWidgets(
      'Lista accesible a $width × $scale, filtro, selección y retorno',
      (tester) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var opened = '';
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            theme: AfTheme.light().copyWith(
              platform: width >= 840
                  ? TargetPlatform.windows
                  : TargetPlatform.android,
            ),
            builder: (context, child) => RepaintBoundary(
              key: drilldownCaptureKey,
              child: MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
            ),
            home: MovementListScreen(
              controller: controller,
              reportOrigin: 'Estado del mes, 03/2026',
              onReturn: () {},
              onOpen: (id) async {
                opened = id;
                await navigator.currentState!.push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const Scaffold(body: Text('Detalle sintético')),
                  ),
                );
              },
            ),
          ),
        );
        await tester.runAsync(() async {
          while (controller.loading) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pumpAndSettle();
        await captureDrilldown(tester, 'movimientos-${width.toInt()}-$scale');
        expect(find.byType(Table), findsNothing);
        expect(find.byType(MovementActivityRow), findsNWidgets(2));
        expect(find.byType(Card), findsNothing);
        await tester.ensureVisible(find.text('Seleccionar página visible (2)'));
        await tester.tap(find.text('Seleccionar página visible (2)'));
        await tester.pump();
        expect(controller.selected.toSet(), {ids[1], ids[2]});
        final semantics = tester.ensureSemantics();
        await tester.ensureVisible(find.byType(Checkbox).first);
        await tester.pump();
        expect(
          find.bySemanticsLabel(RegExp('Seleccionar CAFÉ 2 · ${ids[2]}')),
          findsOneWidget,
        );
        semantics.dispose();
        await tester.ensureVisible(find.text('Abrir CAFÉ 2'));
        final scroll = tester
            .widget<SingleChildScrollView>(
              find.byType(SingleChildScrollView).first,
            )
            .controller!;
        final offset = scroll.offset;
        await tester.tap(find.text('Abrir CAFÉ 2'));
        await tester.pumpAndSettle();
        expect(find.text('Detalle sintético'), findsOneWidget);
        navigator.currentState!.pop();
        await tester.pump();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        });
        await tester.pumpAndSettle();
        expect(opened, ids[2]);
        expect(controller.selected.length, 2);
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Abrir CAFÉ 2'),
              )
              .focusNode!
              .hasFocus,
          isTrue,
        );
        expect(scroll.offset, closeTo(offset, 0.1));
        await tester.enterText(
          find.widgetWithText(TextField, 'Buscar por concepto'),
          'arbol',
        );
        await tester.ensureVisible(find.text('Aplicar filtros'));
        await tester.tap(find.text('Aplicar filtros'));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        });
        await tester.pumpAndSettle();
        expect(controller.page!.records.single.id, ids[0]);
        expect(controller.selected, isEmpty);
        expect(find.text('Nuevo ámbito local'), findsOneWidget);
        await tester.ensureVisible(
          find.text('Restablecer filtros del informe'),
        );
        await tester.tap(find.text('Restablecer filtros del informe'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pumpAndSettle();
        expect(controller.concept, isEmpty);
        expect(controller.page!.totalCount, 3);
        expect(controller.page!.subtotalCents, 600);
        expect(find.text('Filtros del informe'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  test('EUR exactos con signo', () {
    expect(movementEuro(0), '0,00 €');
    expect(movementEuro(-9223372036854775808), '−92.233.720.368.547.758,08 €');
  });
  testWidgets(
    'Fallo de relectura al volver conserva origen sin anunciar borrado',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MovementListScreen(
            controller: controller,
            onReturn: () {},
            onOpen: (_) async {
              fail = true;
            },
          ),
        ),
      );
      await tester.runAsync(() async {
        while (controller.loading) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Abrir CAFÉ 2'));
      await tester.tap(find.text('Abrir CAFÉ 2'));
      await tester.pumpAndSettle();
      expect(controller.page, isNull);
      expect(controller.error, isNotNull);
      expect(controller.notice, isNull);
      expect(controller.from.value, '2026-03-01');
      expect(controller.focus, ids[2]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Gestión e informes conservan mes y selección al redimensionar y volver del detalle',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: AutofinanceApp(
            movements: () async => createMovementListSource(db, invalidation),
          ),
        ),
      );
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.pushNamed('/real?a=2026&m=03');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver movimientos reales'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Periodo 2026-03-01'), findsOneWidget);
      expect(find.byKey(const Key('period-year')), findsNothing);
      expect(find.textContaining('Periodo del informe:'), findsOneWidget);
      await _capture(tester, captureKey, '1440');
      await captureDrilldown(
        tester,
        'movimientos-shell-windows',
        key: captureKey,
      );
      await tester.ensureVisible(find.byType(Checkbox).first);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      final list = tester.widget<MovementListScreen>(
        find.byType(MovementListScreen),
      );
      expect(list.controller.selected, {ids[2]});
      tester.view.physicalSize = const Size(412, 1000);
      await tester.pumpAndSettle();
      await _capture(tester, captureKey, '412');
      await captureDrilldown(
        tester,
        'movimientos-shell-android',
        key: captureKey,
      );
      expect(
        tester
            .widget<MovementListScreen>(find.byType(MovementListScreen))
            .controller,
        same(list.controller),
      );
      expect(list.controller.selected, {ids[2]});
      await tester.ensureVisible(find.text('Abrir CAFÉ 2'));
      await tester.tap(find.text('Abrir CAFÉ 2'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('UUID: ${ids[2]}'), findsOneWidget);
      await tester.ensureVisible(find.text('Volver a Movimientos'));
      await tester.tap(find.text('Volver a Movimientos'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(list.controller.selected, {ids[2]});
      expect(find.byTooltip('Volver a Real anual, 2026'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'Error y filtros inválidos conservan contexto; recuperación y Sin clasificar',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MovementListScreen(
            controller: controller,
            onReturn: () {},
            onOpen: (_) async {},
          ),
        ),
      );
      Future<void> settle() async {
        await tester.runAsync(() async {
          while (controller.loading) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pumpAndSettle();
      }

      await settle();
      controller.selectPage();
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Desde · AAAA-MM-DD'),
        '2026-04-01',
      );
      await tester.ensureVisible(find.text('Aplicar filtros'));
      await tester.tap(find.text('Aplicar filtros'));
      await tester.pump();
      expect(controller.from.value, '2026-03-01');
      expect(controller.selected.length, 2);
      expect(find.textContaining('Filtros sin aplicar:'), findsOneWidget);
      fail = true;
      await tester.runAsync(() => controller.refresh());
      await tester.pumpAndSettle();
      expect(controller.selected.length, 2);
      expect(find.textContaining('Subtotal filtrado:'), findsNothing);
      fail = false;
      final retry = find.widgetWithText(FilledButton, 'Reintentar');
      await tester.ensureVisible(retry);
      await tester.pumpAndSettle();
      await tester.tap(retry);
      await settle();
      expect(controller.page!.subtotalCents, 600);
      expect(controller.selected.length, 2);
      await tester.enterText(
        find.widgetWithText(TextField, 'Desde · AAAA-MM-DD'),
        '2026-03-01',
      );
      final dropdown = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Categoría',
      );
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sin clasificar').last);
      await settle();
      expect(controller.unclassified, isTrue);
      expect(controller.categoryId, isNull);
      expect(controller.page!.records.single.id, ids[0]);
      expect(controller.selected, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Entrada de informe con rama y catálogo inicialmente vacío', (
    tester,
  ) async {
    controller.categoryId = category;
    await tester.pumpWidget(
      MaterialApp(
        home: MovementListScreen(
          controller: controller,
          onReturn: () {},
          onOpen: (_) async {},
        ),
      ),
    );
    await tester.runAsync(() async {
      while (controller.loading) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(controller.page!.records.map((e) => e.id), [ids[2], ids[1]]);
    expect(controller.categoryLabel(category), 'Ocio');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_MOVEMENT_LIST')) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
  final bytes = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  ))!;
  await tester.runAsync(
    () => File('.tools/092-$name.png').writeAsBytes(bytes.buffer.asUint8List()),
  );
  image.dispose();
}
