import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/navigation/app_router.dart';
import 'package:myautofinance/app/navigation/app_routes.dart';
import 'package:myautofinance/app/local_backup_session.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/movements/presentation/category_tree_screen.dart';

void main() {
  late LocalDatabase db;
  late Directory directory;
  late LocalDatabaseStore store;
  late CategoryManagement service;
  late CategoryDetails income, salary, tax, expense;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('category-ui-synthetic-');
    store = LocalDatabaseStore(supportDirectory: () async => directory);
    db = await store.open();
    service = createCategoryManagement(database: db);
    income = await service.create(name: 'INGRESOS', isIncome: true);
    salary = await service.create(name: 'SALARIO', parentId: income.node.id);
    tax = await service.create(name: 'IMPUESTOS', parentId: salary.node.id);
    expense = await service.create(name: 'GASTOS');
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  Future<void> settle(
    WidgetTester tester, {
    bool waitForStorage = true,
    bool Function()? until,
  }) async {
    // Bombea también las lecturas SQLite encadenadas y la validación de tipo.
    for (var turn = 0; turn < 300; turn++) {
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pumpAndSettle();
      final loading =
          find.text('Leyendo categorías…').evaluate().isNotEmpty ||
          find.text('Leyendo categoría…').evaluate().isNotEmpty ||
          find.text('Consultando el estado del mes…').evaluate().isNotEmpty ||
          find.text('Guardando categoría…').evaluate().isNotEmpty;
      if (turn >= 3 &&
          (!waitForStorage || !loading) &&
          (until == null || until())) {
        break;
      }
    }
    await tester.pumpAndSettle();
  }

  Future<void> open(
    WidgetTester tester,
    String route, {
    CategoryManagementLoader? loader,
    Object? arguments,
  }) async {
    await tester.pumpWidget(
      AutofinanceApp(categories: loader ?? () async => service),
    );
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .pushNamed(route, arguments: arguments);
    await settle(tester);
  }

  Future<void> tap(
    WidgetTester tester,
    String text, {
    bool waitForStorage = true,
  }) async {
    final buttons = find.ancestor(
      of: find.text(text),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is ButtonStyleButton ||
            widget is PopupMenuItem ||
            widget is PopupMenuButton,
      ),
    );
    final target = buttons.evaluate().isNotEmpty
        ? buttons.last
        : find.text(text).last;
    await tester.ensureVisible(target);
    await tester.runAsync(() => tester.tap(target));
    await settle(tester, waitForStorage: waitForStorage);
  }

  Future<void> parent(WidgetTester tester, CategoryDetails? value) async {
    await tester.ensureVisible(find.byType(OutlinedButton).first);
    await tester.runAsync(() => tester.tap(find.byType(OutlinedButton).first));
    await tester.pumpAndSettle();
    await tap(
      tester,
      value == null
          ? 'Sin padre · convertir en raíz'
          : '${value.path} · ${value.node.id}',
    );
  }

  Future<int> revision(WidgetTester tester) async =>
      (await tester.runAsync(db.readState))!.revision;
  Future<CategoryDetails> read(WidgetTester tester, String id) async =>
      (await tester.runAsync(() => service.get(id)))!;

  testWidgets('Gestión desde las cinco áreas y retorno al periodo intacto', (
    tester,
  ) async {
    await tester.pumpWidget(AutofinanceApp(categories: () async => service));
    for (final destination in AppRoutes.destinations) {
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      final origin =
          '${destination.path}?a=2026&m=01&rama=${salary.node.id}&alcance=rama&filtro=retencion';
      navigator.pushNamed(origin);
      await tester.pumpAndSettle();
      await tap(tester, 'Gestión');
      await tap(tester, 'Categorías');
      expect(find.byType(CategoryTreeScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        ModalRoute.of(
          tester.element(
            find.descendant(
              of: find.byType(AppBar),
              matching: find.text(destination.label),
            ),
          ),
        )!.settings.name,
        origin,
      );
      navigator.pop();
      await tester.pumpAndSettle();
    }
    expect(await revision(tester), 4);
  });

  for (final width in [320.0, 360.0, 412.0, 839.0, 840.0, 1024.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Árbol y formulario sin recortes a $width y texto $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        debugDefaultTargetPlatformOverride = width >= 840
            ? TargetPlatform.windows
            : TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final boundary = GlobalKey();
        final captures =
            Platform.environment['CATEGORY_CAPTURE'] == '1' &&
            scale == 1 &&
            [320.0, 412.0, 1440.0].contains(width);
        if (captures) {
          await tester.runAsync(() async {
            final loader = FontLoader(width >= 840 ? 'Segoe UI' : 'Roboto');
            final bytes = await File(
              width >= 840 ? 'C:/Windows/Fonts/segoeui.ttf' : '.tools/flutter/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
            ).readAsBytes();
            loader.addFont(Future.value(ByteData.sublistView(bytes)));
            await loader.load();
          });
        }
        Future<void> capture(String name) async {
          if (!captures) return;
          await tester.runAsync(() async {
            final render =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final screenshot = await render.toImage();
            final png = await screenshot.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('.tools/083-${width.toInt()}-$name.png')
                .writeAsBytes(png!.buffer.asUint8List());
            screenshot.dispose();
          });
        }

        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: AutofinanceApp(categories: () async => service),
          ),
        );
        tester
            .state<NavigatorState>(find.byType(Navigator))
            .pushNamed(AppRoutes.categories);
        await settle(tester);
        expect(find.text('INGRESOS / SALARIO / IMPUESTOS'), findsOneWidget);
        expect(
          find.byType(Table),
          width >= 840 ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
        await capture('arbol');
        await tap(tester, 'Crear categoría');
        await tester.enterText(
          find.byType(TextField),
          'Nombre sintético largo con acentos y nombres repetidos',
        );
        await parent(tester, salary);
        expect(find.text('Tipo · solo lectura'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture('formulario');
        await tap(tester, 'Cancelar');
        expect(find.text('Hay cambios sin guardar'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture('confirmacion');
        await tap(tester, 'Descartar cambios');
        expect(await revision(tester), 4);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }

  testWidgets(
    'Alta desde selector devuelve UUID nuevo; cancelar conserva la selección',
    (tester) async {
      CategoryDetails? selected = tax;
      final origin = CategoryNavigationContext(
        returnLabel: 'Volver al selector · enero 2026',
        onCreated: (created) => selected = created,
      );
      await open(tester, AppRoutes.categories, arguments: origin);
      await tap(tester, 'Crear categoría');
      await tester.enterText(find.byType(TextField), 'IMPUESTOS');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tap(tester, 'Descartar cambios');
      expect(selected!.node.id, tax.node.id);
      expect(await revision(tester), 4);
      await tap(tester, 'Crear categoría');
      await tester.enterText(find.byType(TextField), 'IMPUESTOS');
      await parent(tester, salary);
      await tap(tester, 'Crear categoría');
      // El resultado del alta atraviesa dos rutas y la recarga del árbol.
      await settle(tester, until: () => selected!.node.id != tax.node.id);
      expect(selected!.node.id, isNot(tax.node.id));
      expect(selected!.path, tax.path);
      expect(find.text('Marcador técnico · /estado'), findsOneWidget);
      expect(await revision(tester), 5);
    },
  );

  testWidgets(
    'Traslado confirmado adopta tipo, promoción lo conserva y renombre persiste',
    (tester) async {
      await open(tester, '${AppRoutes.categories}/${salary.node.id}');
      await parent(tester, expense);
      await tap(tester, 'Revisar y guardar');
      expect(find.text('Trasladar rama completa'), findsOneWidget);
      expect(find.text('Después: GASTOS / SALARIO · Salida'), findsOneWidget);
      await tap(tester, 'Cancelar');
      expect((await read(tester, salary.node.id)).path, salary.path);
      await tap(tester, 'Revisar y guardar');
      await tap(tester, 'Trasladar rama');
      expect((await read(tester, tax.node.id)).node.isIncome, false);
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed('${AppRoutes.categories}/${salary.node.id}');
      await settle(tester);
      await parent(tester, null);
      expect(find.text('Tipo · solo lectura'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'SUELDO');
      await tap(tester, 'Revisar y guardar');
      await tap(tester, 'Convertir en raíz');
      final promoted = await read(tester, salary.node.id);
      expect(promoted.path, 'SUELDO');
      expect(promoted.node.parentId, isNull);
      expect(promoted.node.isIncome, false);
      expect((await read(tester, tax.node.id)).path, 'SUELDO / IMPUESTOS');
      expect(await revision(tester), 6);
    },
  );

  testWidgets(
    'Archivo/reactivación son de rama completa; bloqueo bajo padre archivado',
    (tester) async {
      await open(tester, '${AppRoutes.categories}/${salary.node.id}');
      await tap(tester, 'Archivar rama completa');
      await tap(tester, 'Cancelar');
      expect(await revision(tester), 4);
      await tap(tester, 'Archivar rama completa');
      await tap(tester, 'Archivar rama');
      expect((await read(tester, tax.node.id)).node.archived, true);
      await tester.runAsync(() => service.archive(income.node.id));
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed('${AppRoutes.categories}/${salary.node.id}');
      await settle(tester);
      await tap(tester, 'Reactivar rama completa');
      await tap(tester, 'Reactivar rama');
      expect(find.text('Reactiva primero la rama padre.'), findsOneWidget);
      expect(await revision(tester), 6);
      await tap(tester, 'Cancelar');
      await tester.runAsync(() => service.reactivate(income.node.id));
      expect((await read(tester, tax.node.id)).node.archived, false);
    },
  );

  testWidgets(
    'Conflicto histórico muestra mes, rutas y UUID; rollback conserva formulario',
    (tester) async {
      final budgets = SqliteBudgetRepository(db);
      await tester.runAsync(
        () => budgets.create(
          BudgetInput(
            month: BudgetMonth(2025, 1),
            categoryId: tax.node.id,
            amountCents: -60000,
          ),
        ),
      );
      await tester.runAsync(
        () => budgets.create(
          BudgetInput(
            month: BudgetMonth(2025, 1),
            categoryId: expense.node.id,
            amountCents: -100000,
          ),
        ),
      );
      await open(tester, '${AppRoutes.categories}/${salary.node.id}');
      await tester.enterText(find.byType(TextField), 'NUEVO SALARIO');
      await parent(tester, expense);
      await tap(tester, 'Revisar y guardar');
      await tap(tester, 'Trasladar rama');
      expect(find.textContaining('enero de 2025:'), findsOneWidget);
      expect(find.textContaining(expense.node.id), findsWidgets);
      expect(find.textContaining(tax.node.id), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'NUEVO SALARIO',
      );
      expect((await read(tester, salary.node.id)).path, salary.path);
      expect(await revision(tester), 6);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Nombre vacío, ciclo y cuarto nivel enfocan el campo y no escriben',
    (tester) async {
      await open(tester, '${AppRoutes.categories}/${income.node.id}');
      await tester.enterText(find.byType(TextField), ' ');
      await tap(tester, 'Revisar y guardar');
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        true,
      );
      await tester.enterText(find.byType(TextField), 'INGRESOS');
      await parent(tester, salary);
      await tap(tester, 'Revisar y guardar');
      expect(find.textContaining('crearía un ciclo.'), findsWidgets);
      await parent(tester, tax);
      await tap(tester, 'Revisar y guardar');
      expect(await revision(tester), 4);
      await tap(tester, 'Cancelar');
      await tap(tester, 'Descartar cambios');
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed(AppRoutes.newCategory);
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'CUARTO');
      await parent(tester, tax);
      await tap(tester, 'Crear categoría');
      expect(find.textContaining('superaría tres niveles.'), findsWidgets);
      expect(await revision(tester), 4);
    },
  );

  testWidgets(
    'Raíz con historia archivada bloquea tipo; raíz vacía permite cambio',
    (tester) async {
      await tester.runAsync(
        () => SqliteBudgetRepository(db).create(
          BudgetInput(
            month: BudgetMonth(2025, 1),
            categoryId: tax.node.id,
            amountCents: 0,
          ),
        ),
      );
      await tester.runAsync(() => service.archive(salary.node.id));
      expect(
        await tester.runAsync(() => service.canChangeRootType(income.node.id)),
        false,
      );
      expect(
        await tester.runAsync(() => service.canChangeRootType(expense.node.id)),
        true,
      );
      await open(tester, '${AppRoutes.categories}/${income.node.id}');
      expect(find.textContaining('Tipo bloqueado:'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<bool>), findsNothing);
      await tap(tester, 'Cancelar');
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed('${AppRoutes.categories}/${expense.node.id}');
      await settle(tester);
      expect(find.byType(DropdownButtonFormField<bool>), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<bool>));
      await tester.pumpAndSettle();
      await tap(tester, 'Ingreso');
      await tap(tester, 'Revisar y guardar');
      expect((await read(tester, expense.node.id)).node.isIncome, true);
    },
  );

  testWidgets(
    'Error de escritura conserva borrador; operación pendiente impide doble guardado y Back',
    (tester) async {
      var calls = 0;
      final pending = Completer<CategoryManagement>();
      await open(
        tester,
        AppRoutes.newCategory,
        loader: () async {
          calls++;
          if (calls == 2) throw const CategoryFailure('Disco no disponible.');
          if (calls == 3) return pending.future;
          return service;
        },
      );
      await tester.enterText(find.byType(TextField), 'NUEVA');
      await tap(tester, 'Crear categoría');
      expect(find.text('Disco no disponible.'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'NUEVA',
      );
      await tap(tester, 'Crear categoría', waitForStorage: false);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Crear categoría'),
            )
            .onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Guardando categoría…'), findsOneWidget);
      expect(calls, 3);
      expect(await revision(tester), 4);
      pending.complete(service);
      await settle(tester);
      expect(await revision(tester), 5);
      await settle(tester);
      expect(find.text('Marcador técnico · /estado'), findsOneWidget);
    },
  );

  testWidgets(
    'Tab, Escape y Back mantienen el borrador y devuelven foco del diálogo',
    (tester) async {
      await open(tester, AppRoutes.newCategory);
      final nameFocus = tester
          .widget<TextField>(find.byType(TextField))
          .focusNode!;
      expect(nameFocus.hasFocus, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        tester
            .widget<OutlinedButton>(find.byType(OutlinedButton).first)
            .focusNode!
            .hasFocus,
        true,
      );
      await tester.enterText(find.byType(TextField), 'BORRADOR');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Hay cambios sin guardar'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Hay cambios sin guardar'), findsNothing);
      expect(nameFocus.hasFocus, true);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tap(tester, 'Seguir editando');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'BORRADOR',
      );
      expect(await revision(tester), 4);
    },
  );

  testWidgets(
    'Error de lectura permite reintento; entidad inexistente permite volver sin escribir',
    (tester) async {
      var fail = true;
      await open(
        tester,
        AppRoutes.categories,
        loader: () async {
          if (fail) throw const CategoryFailure('No se pudo leer SQLite.');
          return service;
        },
      );
      expect(find.text('No se pudo leer SQLite.'), findsOneWidget);
      fail = false;
      await tap(tester, 'Reintentar');
      expect(find.text(tax.path), findsOneWidget);
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed('${AppRoutes.categories}/no-existe');
      await settle(tester);
      expect(find.textContaining('La categoría no existe.'), findsOneWidget);
      await tap(tester, 'Volver a Autofinance');
      expect(find.text(tax.path), findsOneWidget);
      expect(await revision(tester), 4);
    },
  );

  testWidgets(
    'Sesión real comparte SQLite y resuelve la conexión tras reabrir',
    (tester) async {
      await tester.runAsync(store.close);
      final session = LocalBackupSession(
        supportDirectory: () async => directory,
      );
      addTearDown(session.store.close);
      expect(await tester.runAsync(session.open), isTrue);
      await tester.pumpWidget(AutofinanceApp(localSession: session));
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed('${AppRoutes.categories}/${salary.node.id}');
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'SALARIO REABIERTO');
      await tester.runAsync(session.store.close);
      await tap(tester, 'Revisar y guardar');
      service = (await tester.runAsync(session.categories))!;
      db = (await tester.runAsync(session.store.open))!;
      expect(
        (await read(tester, salary.node.id)).path,
        'INGRESOS / SALARIO REABIERTO',
      );
      expect(await revision(tester), 5);
      await settle(tester);
      expect(find.text('Estado del mes'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
    },
  );

  testWidgets('Expansión anunciada y retorno conservan filtro, scroll y foco', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      for (var n = 0; n < 8; n++) {
        await tester.runAsync(
          () => service.create(name: 'ZZZ categoría sintética $n'),
        );
      }
      await open(tester, AppRoutes.categories);
      final toggle = find.widgetWithText(TextButton, '− INGRESOS');
      expect(
        tester
            .getSemantics(toggle)
            .getSemanticsData()
            .flagsCollection
            .isExpanded
            .toBoolOrNull(),
        true,
      );
      await tap(tester, '− INGRESOS');
      expect(find.text(tax.path), findsNothing);
      expect(
        tester
            .getSemantics(find.widgetWithText(TextButton, '+ INGRESOS'))
            .getSemanticsData()
            .flagsCollection
            .isExpanded
            .toBoolOrNull(),
        false,
      );
      await tap(tester, 'Mostrar también archivadas');
      final edit = find.bySemanticsLabel(
        RegExp('Editar ZZZ categoría sintética 7'),
      );
      await tester.ensureVisible(edit);
      final scroll = tester
          .widget<SingleChildScrollView>(
            find.byType(SingleChildScrollView).first,
          )
          .controller!;
      final offset = scroll.offset;
      await tester.runAsync(() => tester.tap(edit));
      await settle(tester);
      await tester.enterText(
        find.byType(TextField),
        'ZZZ categoría sintética 7 editada',
      );
      await tap(tester, 'Revisar y guardar');
      await settle(
        tester,
        until: () {
          final edits = find.widgetWithText(
            OutlinedButton,
            'Editar / gestionar',
          );
          if (edits.evaluate().isEmpty) return false;
          return tester.widget<OutlinedButton>(edits.last).focusNode!.hasFocus;
        },
      );
      expect(find.text(tax.path), findsNothing);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        true,
      );
      expect(scroll.offset, closeTo(offset, 1));
      final restored = tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Editar / gestionar').last,
          )
          .focusNode!;
      expect(restored.hasFocus, true);
    } finally {
      semantics.dispose();
    }
  });
}
