import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/budget_factory.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/navigation/app_router.dart';
import 'package:myautofinance/app/navigation/budget_origin.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/app/navigation/navigation_session_scope.dart';
import 'package:myautofinance/app/regional.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/budget/presentation/budget_source.dart';
import 'package:myautofinance/features/movements/movements.dart';

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
    if (Platform.environment['ANNUAL_ANDROID_VISUAL_QA'] == '1') {
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
    if (Platform.environment['ANNUAL_ANDROID_VISUAL_QA'] != '1') return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('annual-screenshot')),
      );
      final capture = await boundary.toImage();
      final data = await capture.toByteData(format: ImageByteFormat.png);
      await File('.tools/ma-tsk-169-$name.png')
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
  Future<List<BudgetRecord>> records(WidgetTester tester) async =>
      (await tester.runAsync(() => SqliteBudgetRepository(db).readYear(2026)))!;

  Future<void> boot(
    WidgetTester tester, {
    double width = 360,
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
          theme: ThemeData(platform: TargetPlatform.android),
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
    temp = await Directory.systemTemp.createTemp('annual-android-synthetic-');
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

  Finder focused(String id) => find.byKey(ValueKey('cell-$id:01:focused'));
  Finder months(String id) => find.byKey(ValueKey('annual-months-$id'));
  Finder amount() => find.byKey(const Key('budget-form-amount'));

  for (final width in [320.0, 840.0, 1440.0]) {
    testWidgets(
      'Android tarjetas a $width px y texto 200%, tres niveles y doce meses ordenados',
      (tester) async {
        await source.management.create(
          month: january,
          categoryId: leaf,
          amountCents: 0,
        );
        await boot(tester, width: width, scale: 2);
        expect(find.byKey(const Key('matrix-scroll-region')), findsNothing);
        await expand(tester);
        expect(
          find.text('Alimentación / Supermercado / Compra semanal'),
          findsOneWidget,
        );
        await tap(tester, months(leaf));
        final labels = tester
            .widgetList<Text>(
              find.descendant(of: months(leaf), matching: find.byType(Text)),
            )
            .map((w) => w.data)
            .where(
              (s) => const [
                'Enero · Enfocado',
                'Febrero',
                'Marzo',
                'Abril',
                'Mayo',
                'Junio',
                'Julio',
                'Agosto',
                'Septiembre',
                'Octubre',
                'Noviembre',
                'Diciembre',
              ].contains(s),
            )
            .toList();
        expect(labels, [
          'Enero · Enfocado',
          'Febrero',
          'Marzo',
          'Abril',
          'Mayo',
          'Junio',
          'Julio',
          'Agosto',
          'Septiembre',
          'Octubre',
          'Noviembre',
          'Diciembre',
        ]);
        await tester.ensureVisible(cell(leaf, 12));
        await tester.pumpAndSettle();
        await screenshot(tester, '${width.toInt()}-cards-200');
        await tap(tester, cell(leaf, 12));
        await screenshot(tester, '${width.toInt()}-form-200');
        expect(amount(), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('budget-period')))
              .controller!
              .text,
          '2026-12',
        );
        await tester.enterText(amount(), '0');
        await tap(tester, find.text('Guardar partida'));
        expect(
          (await records(tester)).where((r) => r.data.amountCents == 0),
          hasLength(2),
        );
        expect(session.period, NavigationPeriod(2026, 1));
        expect(find.textContaining('0,00 € (registrado)'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Guardar y Android Back conservan ramas, meses abiertos, scroll y foco',
    (tester) async {
      final old = await source.management.create(
        month: january,
        categoryId: leaf,
        amountCents: -5000,
      );
      await boot(tester);
      await expand(tester);
      await tap(tester, months(leaf));
      await tap(tester, cell(leaf, 12));
      final savedOrigin = BudgetOrigin.parse(
        BudgetOrigin(session.context).route,
      ).context;
      expect(savedOrigin.filters['meses'], contains(leaf));
      await tester.enterText(amount(), '-12');
      await tester.runAsync(() => tester.binding.handlePopRoute());
      await settle(tester);
      await tap(tester, find.text('Seguir editando'));
      expect(tester.widget<TextField>(amount()).controller!.text, '-12');
      await tester.runAsync(() => tester.binding.handlePopRoute());
      await settle(tester);
      await tap(tester, find.text('Descartar cambios'));
      expect(await records(tester), hasLength(1));
      expect(
        tester.widget<TextButton>(cell(leaf, 12)).focusNode!.hasFocus,
        isTrue,
      );
      expect(
        session.context.scrollOffset,
        closeTo(savedOrigin.scrollOffset, 1),
      );
      await tap(tester, focused(leaf));
      await tap(tester, find.text('Editar'));
      expect(tester.widget<TextField>(amount()).controller!.text, '-50,00');
      await tester.enterText(amount(), '0');
      await tap(tester, find.text('Guardar partida'));
      expect((await records(tester)).single.id, old.id);
      expect((await records(tester)).single.data.amountCents, 0);
      expect(
        tester.widget<TextButton>(focused(leaf)).focusNode!.hasFocus,
        isTrue,
      );
      expect(session.context.filters['abiertas'], contains(child));
      expect(session.context.filters['meses'], contains(leaf));
      expect(session.period, NavigationPeriod(2026, 1));
    },
  );

  testWidgets(
    'Neto cero abre dos orígenes, ausencia crea, vacío no borra y eliminación confirmada',
    (tester) async {
      await source.management.create(
        month: january,
        categoryId: leaf,
        amountCents: -5000,
      );
      await source.management.create(
        month: january,
        categoryId: sibling,
        amountCents: 5000,
      );
      await boot(tester);
      await tap(tester, find.byKey(ValueKey('total-year-$root')));
      expect(find.text('Partidas del año'), findsOneWidget);
      expect(find.text('Total de partidas: 0,00 €'), findsOneWidget);
      await tap(tester, find.text('Volver al origen'));
      await tap(tester, focused(root));
      expect(find.text('Partidas del mes'), findsOneWidget);
      expect(find.byKey(const Key('annual-cell-input')), findsNothing);
      await tap(tester, find.text('Volver al origen'));
      await tap(tester, focused(empty));
      await tester.enterText(amount(), '0');
      await tap(tester, find.text('Guardar partida'));
      await tap(tester, focused(empty));
      await tap(tester, find.text('Editar'));
      await tester.enterText(amount(), '');
      await tap(tester, find.text('Guardar partida'));
      expect(find.textContaining('Vaciar no elimina'), findsWidgets);
      expect(await records(tester), hasLength(3));
      await tester.enterText(amount(), '0');
      await tap(tester, find.text('Eliminar partida'));
      await tap(tester, find.text('Cancelar').last);
      expect(await records(tester), hasLength(3));
      await tap(tester, find.text('Eliminar partida'));
      await tap(tester, find.widgetWithText(FilledButton, 'Eliminar partida'));
      expect(await records(tester), hasLength(2));
      expect(tester.widget<TextButton>(focused(empty)).onPressed, isNotNull);
    },
  );

  testWidgets(
    'Historial archivado editable, ausencia archivada deshabilitada y alta activa',
    (tester) async {
      final old = await source.management.create(
        month: january,
        categoryId: leaf,
        amountCents: -5000,
      );
      await categories.archive(root);
      await boot(tester);
      await expand(tester);
      await tap(tester, months(leaf));
      expect(tester.widget<TextButton>(cell(leaf, 2)).onPressed, isNull);
      await tap(tester, focused(leaf));
      await tap(tester, find.text('Editar'));
      await tester.enterText(amount(), '-60');
      await tap(tester, find.text('Guardar partida'));
      expect((await records(tester)).single.id, old.id);
      expect((await records(tester)).single.data.amountCents, -6000);
      await tap(tester, focused(empty));
      await tester.enterText(amount(), '-10');
      await tap(tester, find.text('Guardar partida'));
      expect(await records(tester), hasLength(2));
    },
  );

  testWidgets(
    'Conflicto padre-descendiente conserva borrador sin sustitución',
    (tester) async {
      await source.management.create(
        month: BudgetMonth(2026, 2),
        categoryId: root,
        amountCents: -8000,
      );
      await boot(tester);
      await expand(tester);
      await tap(tester, months(leaf));
      await tap(tester, cell(leaf, 2));
      await tester.enterText(amount(), '-5');
      await tap(tester, find.text('Guardar partida'));
      expect(tester.widget<TextField>(amount()).controller!.text, '-5');
      expect(find.textContaining('Alimentación'), findsWidgets);
      expect(await records(tester), hasLength(1));
      expect((await records(tester)).single.data.amountCents, -8000);
    },
  );

  testWidgets(
    'Retorno reconstruido sin pila conserva múltiples despliegues y foco',
    (tester) async {
      await boot(tester);
      await expand(tester);
      await tap(tester, months(child));
      await tap(tester, months(leaf));
      await tap(tester, cell(leaf, 12));
      final origin = BudgetOrigin.parse(BudgetOrigin(session.context).route)
          .context;
      await tester.pumpWidget(const SizedBox());
      await boot(tester, origin: origin);
      expect(origin.filters['meses']!.split(',').toSet(), {child, leaf});
      expect(
        tester.widget<TextButton>(cell(leaf, 12)).focusNode!.hasFocus,
        isTrue,
      );
      expect(session.context.scrollOffset, closeTo(origin.scrollOffset, 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Lectura tardía y error no presentan cifras de otro año; reintento usa año actual',
    (tester) async {
      final blocked = Completer<BudgetSource>();
      var delay = false, fail = false;
      Future<BudgetSource> load() async {
        if (fail) throw StateError('synthetic read');
        if (delay) return blocked.future;
        return source;
      }

      await source.management.create(
        month: january,
        categoryId: empty,
        amountCents: 12345,
      );
      await boot(tester, load: load);
      delay = true;
      await tap(tester, find.text('Actualizar año'));
      delay = false;
      await tap(tester, find.text('Año siguiente'));
      expect(find.text('Total anual 2027'), findsOneWidget);
      blocked.complete(source);
      await settle(tester);
      expect(find.textContaining('123,45'), findsNothing);
      fail = true;
      await tap(tester, find.text('Actualizar año'));
      expect(find.text('Total anual 2027'), findsNothing);
      fail = false;
      await tap(tester, find.text('Reintentar'));
      expect(find.text('Total anual 2027'), findsOneWidget);
      expect(find.textContaining('123,45'), findsNothing);
    },
  );

  testWidgets(
    'Fallo de escritura conserva borrador y permite reintento sin alterar año/mes',
    (tester) async {
      session.setContext(
        NavigationContext(
          destination: SessionDestination.budget,
          period: NavigationPeriod(2026, 10),
        ),
      );
      final old = await source.management.create(
        month: BudgetMonth(2026, 10),
        categoryId: empty,
        amountCents: -5000,
      );
      await db.customStatement(
        "CREATE TRIGGER synthetic_failure BEFORE UPDATE ON budgets BEGIN SELECT RAISE(ABORT, 'synthetic write'); END",
      );
      await boot(tester);
      final focusedOctober = find.byKey(ValueKey('cell-$empty:10:focused'));
      await tap(tester, focusedOctober);
      await tap(tester, find.text('Editar'));
      await tester.enterText(amount(), '-60');
      await tap(tester, find.text('Guardar partida'));
      expect(tester.widget<TextField>(amount()).controller!.text, '-60');
      expect((await records(tester)).single.data.amountCents, -5000);
      await tester.runAsync(
        () => db.customStatement('DROP TRIGGER synthetic_failure'),
      );
      await tap(tester, find.text('Reintentar'));
      expect((await records(tester)).single.id, old.id);
      expect((await records(tester)).single.data.amountCents, -6000);
      expect(session.period, NavigationPeriod(2026, 10));
      expect(
        tester.widget<TextButton>(focusedOctober).focusNode!.hasFocus,
        isTrue,
      );
    },
  );

  test('Contexto valida los UUID de meses y mantiene foco acotado', () {
    final parsed = BudgetOrigin.parse(
      '/presupuesto?a=2026&m=01&meses=$leaf,$child',
    );
    expect(
      BudgetOrigin.parse(parsed.route).context.filters['meses'],
      '$leaf,$child',
    );
    expect(
      () => BudgetOrigin.parse('/presupuesto?a=2026&m=01&meses=invalid'),
      throwsA(isA<MovementFailure>()),
    );
  });
}
