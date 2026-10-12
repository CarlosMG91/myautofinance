import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse, ImageByteFormat;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/budget_factory.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/navigation/app_router.dart';
import 'package:myautofinance/app/navigation/budget_origin.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/app/navigation/navigation_session_scope.dart';
import 'package:myautofinance/app/regional.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/budget/presentation/budget_source.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';

import '../support/recovery_reference.dart';

void main() {
  late Directory temp;
  late LocalDatabase db;
  late CategoryManagement categories;
  late CategoryReadInvalidation invalidation;
  late BudgetSource source;
  late NavigationSession session;
  late String root, child, leaf, sibling, empty;
  final january = BudgetMonth(2026, 1);

  setUpAll(() async {
    if (Platform.environment['ANNUAL_VISUAL_QA'] == '1') {
      for (final (family, path) in [
        ('Roboto', 'C:/Windows/Fonts/segoeui.ttf'),
        (
          'MaterialIcons',
          '.tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ),
      ]) {
        final bytes = await File(path).readAsBytes();
        await (FontLoader(
          family,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
    }
  });

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (Platform.environment['ANNUAL_VISUAL_QA'] != '1') return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('annual-screenshot')),
      );
      final capture = await boundary.toImage();
      final data = await capture.toByteData(format: ImageByteFormat.png);
      await File('.tools/ma-tsk-168-$name.png')
          .writeAsBytes(data!.buffer.asUint8List());
      capture.dispose();
    });
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
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

  Finder cell(String id, int month) =>
      find.byKey(ValueKey('cell-$id:${month.toString().padLeft(2, '0')}'));
  Finder getInput() => find.byKey(const Key('annual-cell-input'));
  Future<List<BudgetRecord>> records(WidgetTester tester) async =>
      (await tester.runAsync(() => SqliteBudgetRepository(db).readYear(2026)))!;

  Future<void> boot(
    WidgetTester tester, {
    double width = 1440,
    double scale = 1,
    BudgetLoader? load,
    NavigationContext? origin,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final initial = origin ?? session.context;
    Route<Object?> generate(RouteSettings settings) => AppRouter.generateRoute(
      settings,
      budgets: load ?? () async => source,
      categories: () async => categories,
      navigationSession: session,
    );
    await tester.pumpWidget(
      NavigationSessionScope(
        session: session,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          locale: AppRegional.locale,
          supportedLocales: AppRegional.supportedLocales,
          localizationsDelegates: AppRegional.delegates,
          navigatorObservers: [NavigationSessionObserver(session)],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(
              key: const Key('annual-screenshot'),
              child: child!,
            ),
          ),
          onGenerateInitialRoutes: (_) => [
            generate(
              RouteSettings(
                name: BudgetOrigin(initial).route,
                arguments: initial,
              ),
            ),
          ],
          onGenerateRoute: generate,
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> expand(WidgetTester tester) async {
    await tap(tester, find.byKey(ValueKey('expand-$root')));
    await tap(tester, find.byKey(ValueKey('expand-$child')));
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('annual-ui-synthetic-');
    db = LocalDatabase(
      NativeDatabase(
        File('${temp.path}/synthetic.sqlite'),
        setup: configureConnection,
      ),
    );
    invalidation = CategoryReadInvalidation();
    categories = createCategoryManagement(
      database: db,
      invalidation: invalidation,
    );
    root = (await categories.create(
      name: 'Alimentación',
      isIncome: false,
    )).node.id;
    child = (await categories.create(
      name: 'Supermercado',
      parentId: root,
    )).node.id;
    leaf = (await categories.create(
      name: 'Compra semanal',
      parentId: child,
    )).node.id;
    sibling = (await categories.create(
      name: 'Reembolso',
      parentId: root,
    )).node.id;
    empty = (await categories.create(name: 'Salud', isIncome: false)).node.id;
    source = createBudgetSource(db, invalidation);
    session = NavigationSession(
      initialContext: NavigationContext(
        destination: SessionDestination.budget,
        period: NavigationPeriod(2026, 1),
      ),
    );
  });
  tearDown(() async {
    session.dispose();
    await invalidation.close();
    await db.close();
    await temp.delete(recursive: true);
  });

  testWidgets(
    'Doce meses, raíces contraídas, ausencia y neto cero abren orígenes sin editar subtotal',
    (tester) async {
      final a = await source.management.create(
        month: january,
        categoryId: leaf,
        amountCents: -5000,
      );
      final b = await source.management.create(
        month: january,
        categoryId: sibling,
        amountCents: 5000,
      );
      await boot(tester);
      expect(find.text('Enero · Enfocado'), findsOneWidget);
      expect(find.text('Diciembre'), findsOneWidget);
      expect(find.text('Total anual'), findsOneWidget);
      expect(cell(leaf, 1), findsNothing);
      expect(find.textContaining('0,00 €\n2 partidas'), findsWidgets);
      expect(cell(empty, 1), findsOneWidget);
      final before = await db.readState();
      await tap(tester, cell(root, 1));
      expect(getInput(), findsNothing);
      expect(find.text('Partidas del mes'), findsOneWidget);
      expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
      expect(
        (await tester.runAsync(
          () => source.entries!.read(
            BudgetListQuery(month: january, categoryId: root),
          ),
        ))!.map((e) => e.record.id).toSet(),
        {a.id, b.id},
      );
      expect((await db.readState()).revision, before.revision);
      await tap(tester, find.text('Volver al origen'));
      await expand(tester);
      expect(cell(leaf, 1), findsOneWidget);
      await screenshot(tester, 'windows');
    },
  );

  testWidgets(
    'Celda confirma solo su partida: foco no guarda, cero existe, vacío no borra y no hay doble envío',
    (tester) async {
      final previous = await source.management.create(
        month: january,
        categoryId: leaf,
        amountCents: -70000,
      );
      await boot(tester);
      await expand(tester);
      await tap(tester, cell(sibling, 1));
      await tester.enterText(getInput(), '0');
      await tap(tester, find.textContaining('Cada confirmación'));
      expect(await records(tester), hasLength(1));
      await tester.tap(getInput());
      await tester.runAsync(
        () => tester.testTextInput.receiveAction(TextInputAction.done),
      );
      await settle(tester);
      expect(find.text('Partida guardada'), findsOneWidget);
      final saved = await records(tester);
      expect(saved, hasLength(2));
      expect(
        saved.singleWhere((r) => r.id == previous.id).data.amountCents,
        -70000,
      );
      expect(
        saved.singleWhere((r) => r.data.categoryId == sibling).data.amountCents,
        0,
      );
      expect(find.textContaining('0,00 € (registrado)'), findsOneWidget);
      await tap(tester, cell(sibling, 1));
      await tester.enterText(getInput(), '');
      await tap(tester, find.byTooltip('Confirmar celda'));
      expect(
        find.textContaining('Vaciar no elimina la partida'),
        findsOneWidget,
      );
      expect(await records(tester), hasLength(2));
      await tester.enterText(getInput(), '+12,34');
      final revision = (await db.readState()).revision;
      await tester.runAsync(() async {
        final button = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.check),
        );
        button.onPressed!();
        button.onPressed!();
      });
      await settle(tester);
      expect((await db.readState()).revision, revision + 1);
      expect(find.textContaining('−687,66 €'), findsWidgets);
    },
  );

  testWidgets(
    'Conflicto con padre conserva borrador y todos los datos; meses independientes',
    (tester) async {
      await source.management.create(
        month: january,
        categoryId: root,
        amountCents: -40000,
      );
      await boot(tester);
      await expand(tester);
      await tap(tester, cell(leaf, 1));
      await tester.enterText(getInput(), '-33,25');
      final revision = (await db.readState()).revision;
      await tap(tester, find.byTooltip('Confirmar celda'));
      expect(
        find.textContaining(
          '2026-01: Alimentación / Supermercado / Compra semanal ↔ Alimentación',
        ),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(getInput()).controller!.text, '-33,25');
      expect((await db.readState()).revision, revision);
      await tap(tester, find.byTooltip('Cancelar edición'));
      await tap(tester, find.text('Descartar cambios'));
      await tap(tester, cell(leaf, 2));
      await tester.enterText(getInput(), '-33,25');
      await tap(tester, find.byTooltip('Confirmar celda'));
      expect(await records(tester), hasLength(2));
      expect(find.textContaining('−433,25 €'), findsWidgets);
    },
  );

  testWidgets(
    'Crear padre desde subtotal rechaza descendientes mediante formulario existente',
    (tester) async {
      await source.management.create(
        month: january,
        categoryId: leaf,
        amountCents: 0,
      );
      await boot(tester);
      await tap(tester, cell(root, 1));
      await tap(tester, find.text('Crear partida'));
      await tester.enterText(
        find.byKey(const Key('budget-form-amount')),
        '-10',
      );
      await tap(tester, find.text('Guardar partida'));
      expect(
        find.textContaining(
          'Alimentación ↔ Alimentación / Supermercado / Compra semanal',
        ),
        findsWidgets,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('budget-form-amount')))
            .controller!
            .text,
        '-10',
      );
      expect(await records(tester), hasLength(1));
    },
  );

  testWidgets(
    'Fallo SQLite conserva borrador/revisión; reintento persiste una vez y refresca totales',
    (tester) async {
      await db.customStatement(
        "CREATE TEMP TRIGGER reject_budget BEFORE INSERT ON budgets BEGIN SELECT RAISE(ABORT,'synthetic'); END",
      );
      await boot(tester);
      await tap(tester, cell(empty, 1));
      await tester.enterText(getInput(), '-25.50');
      final before = await db.readState();
      await tap(tester, find.byTooltip('Confirmar celda'));
      expect(find.text('Partida guardada'), findsNothing);
      expect(tester.widget<TextField>(getInput()).controller!.text, '-25.50');
      expect(await records(tester), isEmpty);
      expect((await db.readState()).revision, before.revision);
      await tester.runAsync(
        () => db.customStatement('DROP TRIGGER reject_budget'),
      );
      await tap(tester, find.byTooltip('Confirmar celda'));
      expect(await records(tester), hasLength(1));
      expect(find.textContaining('−25,50 €\n1 partida'), findsWidgets);
    },
  );

  testWidgets(
    'CSV archivado conserva UUID/procedencia al editar; borrado confirmado refresca y mantiene huella',
    (tester) async {
      await SqliteImportBatchRepository(db).create(
        sha256: 'a' * 64,
        source: ImportSource.historicalCsv,
        originalName: 'sintetico.csv',
        contractVersion: '1',
        budgets: [
          ImportedBudget(
            2,
            BudgetInput.fromHistoricalCsv(
              month: january,
              categoryId: leaf,
              csvAmountCents: 35025,
              concept: '  Histórico  ',
              discretion: ' Necesario ',
            ),
          ),
        ],
      );
      final old = (await SqliteBudgetRepository(db).list(january)).single;
      final provenance = await db
          .customSelect('SELECT * FROM import_rows')
          .get();
      final created =
          (await db.customSelect('SELECT created_at FROM budgets').get())
              .single
              .data;
      await categories.archive(root);
      await boot(tester);
      await expand(tester);
      await tap(tester, cell(leaf, 1));
      await tester.enterText(getInput(), '0');
      await tap(tester, find.byTooltip('Confirmar celda'));
      final edited = (await records(tester)).single;
      expect(edited.id, old.id);
      expect(edited.data.concept, old.data.concept);
      expect(edited.data.discretion, old.data.discretion);
      expect(edited.importRowId, old.importRowId);
      expect(edited.batchId, old.batchId);
      expect(edited.sourceOrdinal, old.sourceOrdinal);
      expect(
        (await db.customSelect('SELECT created_at FROM budgets').get())
            .single
            .data,
        created,
      );
      await tap(tester, cell(leaf, 1));
      await tap(tester, find.byTooltip('Formulario / Eliminar partida'));
      await tap(tester, find.text('Eliminar partida'));
      await tap(tester, find.text('Cancelar').last);
      expect(await records(tester), hasLength(1));
      await tap(tester, find.text('Eliminar partida'));
      await tap(tester, find.widgetWithText(FilledButton, 'Eliminar partida'));
      expect(await records(tester), isEmpty);
      expect(
        (await db.customSelect('SELECT * FROM import_rows').get())
            .map((r) => r.data)
            .toList(),
        provenance.map((r) => r.data).toList(),
      );
      expect(find.textContaining('Este año no tiene partidas'), findsOneWidget);
      expect(cell(leaf, 1), findsNothing);
    },
  );

  testWidgets(
    'Año, destino, Escape y cierre nativo piden descarte; cancelar conserva edición',
    (tester) async {
      await boot(tester);
      await tap(tester, cell(empty, 1));
      await tester.enterText(getInput(), '10');
      await tap(tester, find.text('Año siguiente'));
      await tap(tester, find.text('Seguir editando'));
      expect(session.period.year, 2026);
      expect(tester.widget<TextField>(getInput()).controller!.text, '10');
      await tap(tester, find.byKey(const ValueKey('destination-analysis')));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(session.context.destination, SessionDestination.budget);
      final response = tester.binding.handleRequestAppExit();
      await settle(tester);
      await tap(tester, find.text('Seguir editando'));
      expect(await response, AppExitResponse.cancel);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      await tap(tester, find.text('Seguir editando'));
      await tap(tester, find.text('Año siguiente'));
      await tap(tester, find.text('Descartar cambios'));
      expect(session.period.year, 2027);
      expect(getInput(), findsNothing);
      expect(find.textContaining('Este año no tiene partidas'), findsOneWidget);
      expect(await records(tester), isEmpty);
    },
  );

  testWidgets(
    'Gestión categorías y relectura conservan contexto; invalidación actualiza rutas sin escribir',
    (tester) async {
      await boot(tester);
      await expand(tester);
      await tap(tester, cell(leaf, 1));
      await tester.enterText(getInput(), '-2');
      await tap(tester, find.byKey(const ValueKey('destination-management')));
      await tap(tester, find.text('Seguir editando'));
      expect(getInput(), findsOneWidget);
      await tester.runAsync(() => categories.rename(leaf, name: 'Nueva ruta'));
      await settle(tester);
      expect(tester.widget<TextField>(getInput()).controller!.text, '-2');
      await tap(tester, find.byTooltip('Confirmar celda'));
      expect((await records(tester)).single.data.amountCents, -200);
      expect(find.text('Nueva ruta'), findsOneWidget);
      expect(session.context.filters['abiertas'], contains(root));
    },
  );

  testWidgets(
    'Restauración cambia identidad: escritura se rechaza y borrador se conserva',
    (tester) async {
      await boot(tester);
      await tap(tester, cell(empty, 1));
      await tester.enterText(getInput(), '123');
      final oldSource = source;
      source = BudgetSource(
        query: oldSource.query,
        annual: oldSource.annual,
        management: oldSource.management,
        categories: oldSource.categories,
        identity: Object(),
        entries: oldSource.entries,
      );
      invalidation.invalidate();
      await settle(tester);
      await tap(tester, find.byTooltip('Confirmar celda'));
      expect(
        find.textContaining('La base local se ha sustituido'),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(getInput()).controller!.text, '123');
      expect(await records(tester), isEmpty);
    },
  );

  testWidgets(
    'Respuesta tardía del año anterior no pisa lectura nueva; fallo oculta cifras y reintenta',
    (tester) async {
      final blocked = Completer<BudgetSource>();
      var delay = false, fail = false;
      await boot(
        tester,
        load: () async {
          if (fail) throw const BudgetFailure('Lectura sintética fallida');
          return delay ? blocked.future : source;
        },
      );
      delay = true;
      await tap(tester, find.text('Actualizar año'));
      expect(find.textContaining('Cargando presupuesto anual'), findsOneWidget);
      delay = false;
      await tap(tester, find.text('Año siguiente'));
      expect(session.period.year, 2027);
      blocked.complete(source);
      await settle(tester);
      expect(
        find.text('Año de consulta: 2027 · Mes enfocado: 2027-01'),
        findsOneWidget,
      );
      fail = true;
      await tap(tester, find.text('Actualizar año'));
      expect(find.byKey(const ValueKey('summary-year')), findsNothing);
      fail = false;
      await tap(tester, find.text('Reintentar'));
      expect(find.byKey(const ValueKey('summary-year')), findsOneWidget);
    },
  );

  for (final width in [320.0, 840.0, 1440.0]) {
    testWidgets(
      'Composición adaptable, texto 200% y scroll accesible a $width px',
      (tester) async {
        await source.management.create(
          month: january,
          categoryId: empty,
          amountCents: 0,
        );
        await boot(tester, width: width, scale: 2);
        await tester.ensureVisible(
          width == 1440
              ? cell(empty, 1)
              : find.byKey(ValueKey('cell-$empty:01:focused')),
        );
        await tester.pumpAndSettle();
        await screenshot(tester, '${width.toInt()}-200');
        expect(find.textContaining('0,00 € (registrado)'), findsWidgets);
        if (width == 1440) {
          final before = tester.getRect(find.byKey(ValueKey('expand-$root')));
          await tap(tester, cell(empty, 12));
          expect(getInput(), findsOneWidget);
          final after = tester.getRect(find.byKey(ValueKey('expand-$root')));
          expect(after.left, before.left);
        } else {
          expect(find.text('Los doce meses'), findsWidgets);
          await tap(tester, find.byKey(ValueKey('cell-$empty:01:focused')));
          expect(find.byKey(const Key('budget-form-amount')), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Reducir Windows y trasladar la categoría conservan el editor y el borrador visible',
    (tester) async {
      await boot(tester);
      await expand(tester);
      await tap(tester, cell(leaf, 1));
      await tester.enterText(getInput(), '-19,90');
      tester.view.physicalSize = const Size(840, 1200);
      await settle(tester);
      expect(tester.widget<TextField>(getInput()).controller!.text, '-19,90');
      tester.view.physicalSize = const Size(1440, 1200);
      await settle(tester);
      await tester.runAsync(() => categories.move(leaf, parentId: empty));
      await settle(tester);
      expect(tester.widget<TextField>(getInput()).controller!.text, '-19,90');
      await tap(tester, find.text('Confirmar celda'));
      expect((await records(tester)).single.data.categoryId, leaf);
      expect((await records(tester)).single.data.amountCents, -1990);
    },
  );

  testWidgets(
    'Enlace sin pila reconstruye expansión, scroll horizontal/vertical y foco',
    (tester) async {
      await boot(tester);
      await expand(tester);
      await tap(tester, cell(leaf, 12));
      await tester.enterText(getInput(), '-1');
      await tap(tester, find.byTooltip('Confirmar celda'));
      final origin = BudgetOrigin.parse(BudgetOrigin(session.context).route)
          .context;
      expect(origin.focus, contains('$leaf:12|matrix='));
      await tester.pumpWidget(const SizedBox());
      await boot(tester, origin: origin);
      expect(
        tester.widget<TextButton>(cell(leaf, 12)).focusNode!.hasFocus,
        isTrue,
      );
      final rect = tester.getRect(cell(leaf, 12));
      expect(rect.right, lessThanOrEqualTo(1440));
      expect(rect.left, greaterThan(216));
      await tap(tester, find.text('Captura mensual'));
      final captureOrigin = BudgetOrigin.parse(
        BudgetOrigin(session.context).route,
      ).context;
      await tester.pumpWidget(const SizedBox());
      await boot(tester, origin: captureOrigin);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Captura mensual'),
            )
            .focusNode!
            .hasFocus,
        isTrue,
      );
    },
  );

  testWidgets(
    'Caso E muestra +13200 EUR anual y doce +1100 EUR con 48 UUID sin doble conteo',
    (tester) async {
      await seedRecoveryReference(db);
      await boot(tester);
      expect(find.textContaining('+13.200,00 €\n48 partidas'), findsWidgets);
      expect(find.textContaining('+1.100,00 €\n4 partidas'), findsNWidgets(12));
      await tap(tester, find.byKey(const ValueKey('summary-year')));
      expect(
        (await tester.runAsync(
          () => source.entries!.read(BudgetListQuery.annual(2026)),
        ))!,
        hasLength(48),
      );
      expect(find.text('Partidas del año'), findsOneWidget);
    },
  );

  testWidgets(
    'Flechas desplazan cifras y cabecera conjuntamente con categoría fija',
    (tester) async {
      await boot(tester);
      final category = tester.getRect(find.byKey(ValueKey('expand-$root')));
      final januaryRect = tester.getRect(find.text('Enero · Enfocado'));
      tester
          .widget<Focus>(find.byKey(const Key('matrix-scroll-region')))
          .focusNode!
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await settle(tester);
      expect(
        tester.getRect(find.text('Enero · Enfocado')).left,
        lessThan(januaryRect.left),
      );
      expect(
        tester.getRect(find.byKey(ValueKey('expand-$root'))).left,
        category.left,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await settle(tester);
      expect(
        tester.getRect(find.text('Enero · Enfocado')).left,
        januaryRect.left,
      );
    },
  );

  testWidgets(
    'Cambiar mes enfocado reinicia posición/foco del origen sin perder el año',
    (tester) async {
      await boot(tester);
      await expand(tester);
      await tap(tester, cell(leaf, 12));
      await tester.enterText(getInput(), '0');
      await tap(tester, find.byTooltip('Confirmar celda'));
      expect(session.context.focus, contains('$leaf:12'));
      await tester.runAsync(
        () => session.selectPeriod(NavigationPeriod(2026, 2)),
      );
      await settle(tester);
      expect(session.context.focus, isNull);
      expect(session.context.scrollOffset, 0);
      expect(find.text('Febrero · Enfocado'), findsOneWidget);
      expect((await records(tester)).single.data.month.value, '2026-12-01');
    },
  );
}
