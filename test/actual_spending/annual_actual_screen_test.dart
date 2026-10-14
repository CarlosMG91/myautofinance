import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/annual_actual_query_factory.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/movement_list_factory.dart';
import 'package:myautofinance/app/navigation/app_router.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/app/navigation/navigation_session_scope.dart';
import 'package:myautofinance/app/navigation/annual_actual_origin.dart';
import 'package:myautofinance/app/regional.dart';
import 'package:myautofinance/features/actual_spending/actual_spending.dart';
import 'package:myautofinance/features/actual_spending/presentation/annual_actual_screen.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

import '../ui/kit_test.dart' show loadAfFonts;

void main() {
  late LocalDatabase db;
  late CategoryReadInvalidation invalidation;
  late CategoryManagement categories;
  late SqliteMovementRepository movements;
  late NavigationSession session;
  late AnnualActualQuery query;
  late String account, secondAccount, root, child, leaf, saving, archived;
  setUpAll(loadAfFonts);
  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
    invalidation = CategoryReadInvalidation();
    categories = createCategoryManagement(
      database: db,
      invalidation: invalidation,
    );
    movements = SqliteMovementRepository(db);
    query = createAnnualActualQuery(database: db, invalidation: invalidation);
    session = NavigationSession(
      initialContext: NavigationContext(
        destination: SessionDestination.actual,
        period: NavigationPeriod(2026, 2),
      ),
    );
    Future<String> newAccount(String name) async =>
        (await SqliteAccountRepository(db).create(
          name: name,
          kind: AccountKind.account,
          activeFrom: Month(2026, 1),
          liquidity: Liquidity.liquid,
        )).id;
    account = await newAccount('Cuenta sintética');
    secondAccount = await newAccount('Otra cuenta sintética');
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
    saving = (await categories.create(name: 'Ahorro', isIncome: false)).node.id;
    archived = (await categories.create(name: 'Ocio', isIncome: false)).node.id;
    final income = (await categories.create(
      name: 'Ingresos',
      isIncome: true,
    )).node.id;
    await categories.create(name: 'Salud', isIncome: false);
    Future<void> real(
      String? id,
      int amount,
      String concept, {
      int month = 1,
      String? onAccount,
    }) async {
      await movements.create(
        MovementInput(
          accountId: onAccount ?? account,
          valueDate: ValueDate(2026, month, 9),
          concept: concept,
          amountCents: amount,
          categoryId: id,
        ),
      );
    }

    await real(root, -1200, 'Directo raíz');
    await real(child, 200, 'Directo hijo');
    await real(leaf, -12345, 'Compra sintética');
    await real(saving, -50000, 'Transferencia salida');
    await real(
      saving,
      50000,
      'Transferencia entrada',
      onAccount: secondAccount,
    );
    await real(null, 400, 'Sin categoría');
    await real(archived, -2000, 'Histórico archivado');
    await real(income, 300000, 'Ingreso enero');
    await real(income, 310000, 'Ingreso febrero', month: 2);
    await real(root, -5000, 'Compra diciembre', month: 12);
    await categories.archive(archived);
  });
  tearDown(() async {
    session.dispose();
    await invalidation.close();
    await db.close();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
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
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> boot(
    WidgetTester tester, {
    bool detail = false,
    double width = 1440,
    double scale = 1,
    TargetPlatform platform = TargetPlatform.windows,
    String? route,
    AnnualActualLoader? loader,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1000);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    Route<Object?> generate(RouteSettings settings) => AppRouter.generateRoute(
      settings,
      annualActual: loader ?? () async => query,
      movements: () async => createMovementListSource(db, invalidation),
      categories: () async => categories,
      navigationSession: session,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AfTheme.light().copyWith(platform: platform),
        locale: AppRegional.locale,
        supportedLocales: AppRegional.supportedLocales,
        localizationsDelegates: AppRegional.delegates,
        navigatorObservers: [NavigationSessionObserver(session)],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(
            key: const Key('actual-capture'),
            child: child!,
          ),
        ),
        onGenerateInitialRoutes: (_) => [
          generate(
            RouteSettings(
              name:
                  route ??
                  AnnualActualOrigin(session.context, detail: detail).route,
            ),
          ),
        ],
        onGenerateRoute: generate,
      ),
    );
    await settle(tester);
  }

  TextButton button(WidgetTester tester, String id) =>
      tester.widget<TextButton>(find.byKey(ValueKey('actual-$id')));
  String amount(WidgetTester tester, String id) =>
      (button(tester, id).child! as AfMoneyText).amount.format();

  testWidgets(
    'Resumen y serie usan doce cifras firmadas; detalle íntegro y árbol tres niveles',
    (tester) async {
      await boot(tester);
      final data = await query.read(2026);
      expect(
        amount(tester, 'summary-all:year'),
        AfAmount(data.annualTotal.amountCents).format(),
      );
      final chart = tester.widget<AfTimeChart>(find.byType(AfTimeChart));
      expect(
        chart.series.single.points.map((p) => p.value.formatted),
        data.months.map((m) => AfChartValue.euros(m.amountCents).formatted),
      );
      expect(chart.series.single.points, hasLength(12));
      expect(find.byType(AfDetailTable), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('actual-show-detail')));
      await tester.pumpAndSettle();
      final summaryOffset = session.context.scrollOffset;
      await tap(tester, find.byKey(const Key('actual-show-detail')));
      var table = tester.widget<AfDetailTable>(find.byType(AfDetailTable));
      expect(table.columns, hasLength(13));
      expect(table.rows.where((r) => r.depth > 0), isEmpty);
      expect(table.rows.any((r) => r.label == 'Ocio · Archivada'), isTrue);
      expect(table.rows.any((r) => r.label == 'Sin clasificar'), isTrue);
      table.rows.singleWhere((r) => r.label == 'Alimentación').onExpand!();
      await settle(tester);
      table = tester.widget<AfDetailTable>(find.byType(AfDetailTable));
      table.rows
          .singleWhere((r) => r.label == 'Alimentación / Supermercado')
          .onExpand!();
      await settle(tester);
      expect(amount(tester, '$root:1'), '−133,45 €');
      expect(amount(tester, '$child:1'), '−121,45 €');
      expect(amount(tester, '$leaf:1'), '−123,45 €');
      expect(amount(tester, 'sin-clasificar:1'), '+4,00 €');
      expect(
        tester
            .widget<AfDetailTable>(find.byType(AfDetailTable))
            .rows
            .any((r) => r.depth == 2),
        isTrue,
      );
      expect(find.byType(TextFormField), findsNothing);
      await tap(tester, find.text('Volver al resumen'));
      expect(session.period, NavigationPeriod(2026, 2));
      expect(session.context.scrollOffset, closeTo(summaryOffset, .1));
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('actual-show-detail')))
            .focusNode!
            .hasFocus,
        isTrue,
      );
    },
  );

  testWidgets(
    'Cero neto abre dos registros y retorno restaura ramas, foco y scroll',
    (tester) async {
      await boot(tester, detail: true);
      final table = tester.widget<AfDetailTable>(find.byType(AfDetailTable));
      table.rows.singleWhere((r) => r.label == 'Alimentación').onExpand!();
      await settle(tester);
      table.horizontalController!.jumpTo(300);
      await tester.pump();
      expect(amount(tester, '$saving:1'), '0,00 €');
      // Pulsar la cifra después de volver a su columna conserva posición visible.
      table.horizontalController!.jumpTo(0);
      await tap(tester, find.byKey(ValueKey('actual-$saving:1')));
      expect(find.text('Transferencia salida'), findsWidgets);
      expect(find.text('Transferencia entrada'), findsWidgets);
      await tap(tester, find.text('Volver a Real anual, 2026'));
      expect(session.period, NavigationPeriod(2026, 2));
      expect(session.context.filters['abiertas'], contains(root));
      expect(button(tester, '$saving:1').focusNode!.hasFocus, isTrue);
      // Scroll horizontal exacto tras lista anual.
      final current = tester.widget<AfDetailTable>(find.byType(AfDetailTable));
      current.horizontalController!.jumpTo(
        current.horizontalController!.position.maxScrollExtent,
      );
      await tap(tester, find.byKey(ValueKey('actual-$saving:year')));
      await tap(tester, find.text('Volver a Real anual, 2026'));
      final returned = tester.widget<AfDetailTable>(find.byType(AfDetailTable));
      expect(
        returned.horizontalController!.offset,
        returned.horizontalController!.position.maxScrollExtent,
      );
      expect(button(tester, '$saving:year').focusNode!.hasFocus, isTrue);
    },
  );

  testWidgets(
    'Nulo y lista vacía son navegables; añadir usa mes enfocado y vuelve',
    (tester) async {
      await boot(tester, detail: true);
      await tap(tester, find.byKey(const ValueKey('actual-sin-clasificar:1')));
      expect(find.text('Sin categoría'), findsWidgets);
      expect(find.text('Ingreso enero'), findsNothing);
      await tap(tester, find.text('Volver a Real anual, 2026'));
      await tap(tester, find.byKey(const ValueKey('actual-sin-clasificar:2')));
      expect(find.textContaining('No hay movimientos'), findsWidgets);
      await tap(tester, find.text('Volver a Real anual, 2026'));
      await tap(tester, find.text('Añadir movimiento'));
      final date = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Fecha de valor · AAAA-MM-DD'),
      );
      expect(date.controller!.text, '2026-02-01');
      await tap(tester, find.text('Volver a Movimientos'));
      expect(session.period, NavigationPeriod(2026, 2));
    },
  );

  testWidgets(
    'Cambio año oculta datos, descarta respuesta tardía; error reintentable y vacío cero',
    (tester) async {
      final delayed = Completer<AnnualActualQuery>();
      var calls = 0;
      var fail = false;
      await boot(
        tester,
        loader: () {
          calls++;
          if (calls == 2) return delayed.future;
          if (fail) return Future.error(StateError('synthetic'));
          return Future.value(query);
        },
      );
      await session.selectYear(2027);
      await tester.pump();
      expect(find.byType(AfTimeChart), findsNothing);
      expect(find.text('Cargando real anual…'), findsOneWidget);
      await session.selectYear(2028);
      await settle(tester);
      expect(amount(tester, 'summary-all:year'), '0,00 €');
      delayed.complete(query);
      await settle(tester);
      expect(
        tester.widget<AfTimeChart>(find.byType(AfTimeChart)).period,
        'Año 2028',
      );
      fail = true;
      await session.selectYear(2029);
      await settle(tester);
      expect(find.byType(AfTimeChart), findsNothing);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('0,00 €'), findsNothing);
      fail = false;
      await tap(tester, find.text('Reintentar'));
      expect(amount(tester, 'summary-all:year'), '0,00 €');
    },
  );

  testWidgets(
    'Invalidación relee catálogo y nueva conexión tras restauración/importación',
    (tester) async {
      var currentDb = db;
      await boot(
        tester,
        detail: true,
        loader: () async => createAnnualActualQuery(
          database: currentDb,
          invalidation: invalidation,
        ),
      );
      await tester.runAsync(() => categories.rename(root, name: 'Comida'));
      await settle(tester);
      expect(
        tester
            .widget<AfDetailTable>(find.byType(AfDetailTable))
            .rows
            .any((r) => r.label == 'Comida'),
        isTrue,
      );
      final replacement = LocalDatabase(
        NativeDatabase.memory(setup: configureConnection),
      );
      currentDb = replacement;
      invalidation.invalidate();
      await settle(tester);
      expect(amount(tester, 'all:year'), '0,00 €');
      expect(
        tester.widget<AfDetailTable>(find.byType(AfDetailTable)).rows,
        hasLength(2),
      );
      await tester.pumpWidget(const SizedBox());
      await replacement.close();
    },
  );

  testWidgets(
    'Entrada sin pila recupera expansión y posiciones; flechas desplazan sin editar',
    (tester) async {
      final origin = NavigationContext(
        destination: SessionDestination.actual,
        period: NavigationPeriod(2026, 2),
        filters: {'abiertas': '$root,$child'},
        focus: 'matrix|matrix=1200.000,30.000',
      );
      await boot(tester, route: AnnualActualOrigin(origin, detail: true).route);
      final table = tester.widget<AfDetailTable>(find.byType(AfDetailTable));
      expect(table.rows.any((r) => r.depth == 2), isTrue);
      expect(table.horizontalController!.offset, 1200);
      final region = tester.widget<Focus>(
        find.byKey(const Key('actual-matrix-region')),
      );
      region.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        table.horizontalController!.offset,
        1360.0.clamp(0, table.horizontalController!.position.maxScrollExtent),
      );
    },
  );

  testWidgets(
    'Editar, borrar y categorizar desde el origen refresca las cifras al volver',
    (tester) async {
      await boot(tester, detail: true);
      await tap(tester, find.byKey(const ValueKey('actual-sin-clasificar:1')));
      await tap(tester, find.text('Abrir Sin categoría'));
      await tap(tester, find.text('Editar'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Importe firmado (EUR)'),
        '9,50',
      );
      await tap(tester, find.text('Guardar movimiento'));
      await tap(tester, find.text('Volver a Real anual, 2026'));
      expect(amount(tester, 'sin-clasificar:1'), '+9,50 €');
      await tap(tester, find.byKey(const ValueKey('actual-sin-clasificar:1')));
      await tap(tester, find.text('Abrir Sin categoría'));
      await tap(tester, find.text('Borrar movimiento'));
      await tap(tester, find.text('Confirmar borrado'));
      await tap(tester, find.text('Volver a Real anual, 2026'));
      expect(amount(tester, 'sin-clasificar:1'), '0,00 €');
      // La escritura usa el repositorio propietario; el informe relee al volver.
      await tap(tester, find.byKey(ValueKey('actual-$root:1')));
      await tester.runAsync(() async {
        final record = (await movements.list(
          from: ValueDate(2026, 1, 1),
          until: ValueDate(2026, 2, 1),
          categoryId: root,
        )).first;
        await movements.setCategoryBatch([record.id], null);
      });
      await tap(tester, find.text('Volver a Real anual, 2026'));
      expect(amount(tester, 'sin-clasificar:1'), isNot('0,00 €'));
      expect(session.period, NavigationPeriod(2026, 2));
    },
  );

  testWidgets('Ruta inválida falla antes de leer', (tester) async {
    var calls = 0;
    await boot(
      tester,
      route: '/real/detalle?a=2026&m=13',
      loader: () async {
        calls++;
        return query;
      },
    );
    expect(calls, 0);
    expect(find.text('Error de navegación'), findsOneWidget);
  });

  for (final (name, width, scale, platform, detail) in [
    ('windows-resumen', 1440.0, 1.0, TargetPlatform.windows, false),
    ('windows-detalle', 1440.0, 1.0, TargetPlatform.windows, true),
    ('android-resumen', 412.0, 1.0, TargetPlatform.android, false),
    ('android-detalle', 412.0, 1.0, TargetPlatform.android, true),
    ('estrecho-texto-200', 320.0, 2.0, TargetPlatform.windows, true),
  ]) {
    testWidgets('Kit visual $name y reflujo sin overflow', (tester) async {
      await boot(
        tester,
        width: width,
        scale: scale,
        platform: platform,
        detail: detail,
      );
      if (width < 840 && detail) {
        expect(find.byType(AfDetailTable), findsNothing);
        await tap(tester, find.byKey(ValueKey('actual-months-$saving')));
        expect(find.byKey(ValueKey('actual-$saving:12')), findsOneWidget);
        // Volver al inicio para inspeccionar shell, periodo y cards.
        for (final scroll in tester.widgetList<SingleChildScrollView>(
          find.byType(SingleChildScrollView),
        )) {
          if (scroll.controller?.hasClients == true) {
            scroll.controller!.jumpTo(0);
          }
        }
        await tester.pumpAndSettle();
      }
      if (scale > 1) {
        await tester.ensureVisible(find.text('Detalle del real anual'));
        await tester.pumpAndSettle();
      }
      await expectLater(
        find.byKey(const Key('actual-capture')),
        matchesGoldenFile('goldens/$name.png'),
      );
    });
  }
}
