import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/budget_factory.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/monthly_status_query_factory.dart';
import 'package:myautofinance/app/movement_list_factory.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/monthly_status/monthly_status.dart';
import 'package:myautofinance/features/monthly_status/presentation/monthly_status_screen.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void androidTest(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      body,
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('STATUS_CAPTURE')) return;
    for (final fontName in ['Segoe UI', 'Roboto']) {
      final font = FontLoader(fontName);
      font.addFont(
        File('C:/Windows/Fonts/segoeui.ttf')
            .readAsBytes()
            .then((bytes) => ByteData.sublistView(bytes)),
      );
      await font.load();
    }
    final icons = FontLoader('MaterialIcons');
    icons.addFont(
      File(
        '.tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
    );
    await icons.load();
  });
  late LocalDatabase db;
  late CategoryReadInvalidation invalidation;
  late CategoryManagement categories;
  late NavigationSession session;
  late String root, child, leaf, empty, zero, account;
  late SqliteMovementRepository movements;
  late SqliteBudgetRepository budgets;
  final jan = BudgetMonth(2026, 1);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
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

  Future<void> backToStatus(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await settle(tester);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('STATUS_CAPTURE')) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('status-capture')),
      );
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('.tools/161-$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<MonthlyStatusQuery> load() async {
    return createMonthlyStatusQuery(database: db, invalidation: invalidation);
  }

  Future<void> boot(
    WidgetTester tester, {
    double width = 320,
    double scale = 1,
    MonthlyStatusLoader? loader,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(scale),
        ),
        child: RepaintBoundary(
          key: const Key('status-capture'),
          child: AutofinanceApp(
            navigationSession: session,
            monthlyStatus: loader ?? load,
            budgets: () async => createBudgetSource(db, invalidation),
            movements: () async => createMovementListSource(db, invalidation),
            categories: () async => categories,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> real(String? category, int cents) => movements.create(
    MovementInput(
      accountId: account,
      valueDate: ValueDate(2026, 1, 9),
      concept: 'Movimiento sintético',
      amountCents: cents,
      categoryId: category,
    ),
  );

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
    invalidation = CategoryReadInvalidation();
    categories = createCategoryManagement(
      database: db,
      invalidation: invalidation,
    );
    movements = SqliteMovementRepository(db);
    budgets = SqliteBudgetRepository(db);
    session = NavigationSession(
      initialContext: NavigationContext(
        destination: SessionDestination.status,
        period: NavigationPeriod(2026, 1),
      ),
    );
    account = (await SqliteAccountRepository(db).create(
      name: 'Cuenta sintética',
      kind: AccountKind.account,
      activeFrom: Month(1, 1),
      liquidity: Liquidity.liquid,
    )).id;
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
    empty = (await categories.create(name: 'Ocio', isIncome: false)).node.id;
    zero = (await categories.create(name: 'Cero', isIncome: false)).node.id;
    await budgets.create(
      BudgetInput(month: jan, categoryId: root, amountCents: -40000),
    );
    await budgets.create(
      BudgetInput(month: jan, categoryId: zero, amountCents: 0),
    );
    await real(leaf, -35025);
    await real(empty, -1000);
    await real(empty, 1000);
    await real(null, -100);
  });
  tearDown(() async {
    session.dispose();
    await invalidation.close();
    await db.close();
  });

  androidTest(
    'Android ancho conserva tarjetas, columnas y objetivos táctiles',
    (tester) async {
      await boot(tester, width: 1200);
      expect(find.byKey(const ValueKey('monthly-status-table')), findsNothing);
      expect(
        find.byKey(const ValueKey('monthly-status-cards')),
        findsOneWidget,
      );
      expect(find.textContaining('Supermercado'), findsNothing);
      expect(find.text('−400,00 €'), findsNWidgets(3));
      expect(find.text('−351,25 €'), findsNWidgets(3));
      expect(find.text('0,00 € (registrado)'), findsOneWidget);
      expect(find.text('Sin presupuesto'), findsNWidgets(2));
      for (final token in [
        'status-add',
        'status-refresh',
        '$root:expandir',
        '$root:real',
        '$root:directo',
      ]) {
        final size = tester.getSize(find.byKey(ValueKey(token)));
        expect(size.height, greaterThanOrEqualTo(48), reason: token);
        expect(size.width, greaterThanOrEqualTo(48), reason: token);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  androidTest(
    '320px y texto 200%: tres niveles, semántica, cifras completas y Back',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await boot(tester, scale: 2);
      final title = tester.renderObject<RenderParagraph>(
        find.text('Estado del mes'),
      );
      expect(title.didExceedMaxLines, isFalse);
      expect(
        tester.getRect(find.byKey(const ValueKey('destination-more'))).right,
        lessThanOrEqualTo(320),
      );
      await tap(tester, find.byKey(ValueKey('$root:expandir')));
      await tap(tester, find.byKey(ValueKey('$child:expandir')));
      expect(
        find.text('Alimentación / Supermercado / Compra semanal'),
        findsOneWidget,
      );
      expect(find.text('Real directo'), findsNWidgets(7));
      expect(find.text('Real agregado'), findsNWidgets(8));
      final direct = find.byKey(ValueKey('$leaf:directo'));
      await tester.ensureVisible(direct);
      expect(
        find.bySemanticsLabel(RegExp('Real directo.*Solo este nodo')),
        findsWidgets,
      );
      final offset = session.context.scrollOffset;
      await capture(tester, 'android-200');
      await tap(tester, direct);
      expect(find.textContaining('Movimiento sintético'), findsWidgets);
      await backToStatus(tester);
      expect(session.context.filters['abiertas'], contains(child));
      expect(session.context.scrollOffset, closeTo(offset, 1));
      expect(FocusManager.instance.primaryFocus?.debugLabel, '$leaf:directo');
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );

  androidTest(
    'Fuentes directo/rama, neto cero, Sin clasificar y diferencia con Back',
    (tester) async {
      await boot(tester);
      await tap(tester, find.byKey(ValueKey('$root:directo')));
      expect(
        find.text(
          'No hay movimientos que coincidan con este periodo y filtros.',
        ),
        findsOneWidget,
      );
      await backToStatus(tester);
      await tap(tester, find.byKey(ValueKey('$root:real')));
      expect(find.text('Movimiento sintético'), findsOneWidget);
      await backToStatus(tester);
      await tap(tester, find.byKey(ValueKey('$empty:real')));
      expect(find.text('Movimiento sintético'), findsNWidgets(2));
      await backToStatus(tester);
      await tap(tester, find.byKey(const ValueKey('sin-clasificar:real')));
      expect(find.text('Movimiento sintético'), findsOneWidget);
      await backToStatus(tester);
      await tap(tester, find.byKey(ValueKey('$root:diferencia')));
      expect(find.text('Ver movimientos reales'), findsOneWidget);
      expect(find.text('Ver partidas previstas'), findsOneWidget);
      await backToStatus(tester);
      expect(find.text('Origen de la diferencia'), findsNothing);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        '$root:diferencia',
      );
      await tap(tester, find.byKey(ValueKey('$root:diferencia')));
      await tap(tester, find.text('Ver partidas previstas'));
      expect(find.text('−400,00 €'), findsWidgets);
      expect(find.textContaining('Compra semanal'), findsNothing);
      await backToStatus(tester);
      await tap(tester, find.byKey(const ValueKey('total:real')));
      expect(find.text('Movimiento sintético'), findsNWidgets(4));
      await tester.pumpWidget(const SizedBox());
    },
  );

  androidTest(
    'Carga, vacío, sin presupuesto, error y respuesta tardía de otro mes',
    (tester) async {
      final held = Completer<MonthlyStatusQuery>();
      var count = 0;
      Future<MonthlyStatusQuery> loader() async {
        count++;
        if (count == 2) return held.future;
        if (count == 4) throw StateError('Fallo sintético');
        return load();
      }

      await boot(tester, loader: loader);
      await tap(tester, find.byKey(const ValueKey('status-refresh')));
      expect(find.text('Consultando el estado del mes…'), findsOneWidget);
      expect(find.text('−351,25 €'), findsNothing);
      await session.selectPeriod(NavigationPeriod(2026, 2));
      await settle(tester);
      expect(
        find.text('No hay movimientos en este mes. Real: 0,00 €.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Sin presupuesto en este mes.'),
        findsOneWidget,
      );
      expect(find.text('0,00 € (registrado)'), findsNothing);
      held.complete(await load());
      await settle(tester);
      expect(find.text('−351,25 €'), findsNothing);
      await tap(tester, find.byKey(const ValueKey('status-refresh')));
      expect(
        find.text(
          'No se pudo consultar el estado del mes. Inténtalo de nuevo.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('monthly-status-cards')), findsNothing);
      expect(
        tester
            .getSize(find.widgetWithText(OutlinedButton, 'Reintentar'))
            .height,
        greaterThanOrEqualTo(48),
      );
      await tap(tester, find.text('Reintentar'));
      expect(
        find.text('No hay movimientos en este mes. Real: 0,00 €.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  androidTest(
    'Editar real y partida actualiza tarjetas y Back protege borradores',
    (tester) async {
      await boot(tester);
      await tap(tester, find.byKey(ValueKey('$root:previsto')));
      await tap(tester, find.text('Abrir'));
      await tap(tester, find.text('Editar'));
      await tester.enterText(
        find.byKey(const Key('budget-form-amount')),
        '-450,00',
      );
      await tap(tester, find.text('Guardar partida'));
      await backToStatus(tester);
      expect(find.text('−450,00 €'), findsNWidgets(3));
      await tap(tester, find.byKey(ValueKey('$root:real')));
      await tap(tester, find.text('Abrir Movimiento sintético'));
      await tap(tester, find.text('Editar'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Importe firmado (EUR)'),
        '-360,25',
      );
      await settle(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('Hay cambios sin guardar'), findsOneWidget);
      await tap(tester, find.text('Seguir editando'));
      await tap(tester, find.text('Guardar movimiento'));
      await backToStatus(tester);
      expect(find.text('−361,25 €'), findsNWidgets(3));
      expect(find.text('+88,75 €\nA favor'), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
    },
  );
  androidTest('Añadir y categorizar persiste, vuelve al mes y conserva total', (
    tester,
  ) async {
    await boot(tester);
    await tap(tester, find.byKey(const ValueKey('status-add')));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Concepto'),
      'Alta Android sintética',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Importe firmado (EUR)'),
      '-12,00',
    );
    await tap(tester, find.byType(DropdownButtonFormField<String>));
    await tap(tester, find.textContaining('Cuenta sintética ·').last);
    await tap(tester, find.text('Guardar movimiento'));
    expect(find.text('−363,25 €'), findsNWidgets(3));
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'status-add');
    expect(session.period, NavigationPeriod(2026, 1));
    await tap(tester, find.byKey(const ValueKey('sin-clasificar:real')));
    await tap(tester, find.text('Abrir Alta Android sintética'));
    await tap(tester, find.text('Editar'));
    await tap(tester, find.text('Seleccionar categoría'));
    await tap(
      tester,
      find.text('Alimentación / Supermercado / Compra semanal'),
    );
    await tap(tester, find.text('Seleccionar'));
    await tap(tester, find.text('Guardar movimiento'));
    await backToStatus(tester);
    expect(
      find.text('−363,25 €'),
      findsNWidgets(3),
    ); // resumen y dos cifras del total
    expect(find.text('−362,25 €'), findsOneWidget); // raíz, sin prorrateo
    final query = await load();
    final result = await tester.runAsync(() => query.read(jan));
    expect(result!.unclassified.actualCents, -100);
    expect(result.total.actualCents, -36325);
    expect(
      result.rows
          .singleWhere((row) => row.categoryId == leaf)
          .actualDirectCents,
      -36225,
    );
    await tester.pumpWidget(const SizedBox());
  });

  androidTest(
    'Histórico archivado y magnitudes grandes no se recortan a 320px/200%',
    (tester) async {
      await categories.archive(child);
      await real(root, 123456789012345);
      await boot(tester, scale: 2);
      await tap(tester, find.byKey(ValueKey('$root:expandir')));
      await tap(tester, find.byKey(ValueKey('$child:expandir')));
      expect(find.textContaining('Compra semanal · Archivada'), findsOneWidget);
      expect(find.text('+1.234.567.890.123,45 €'), findsOneWidget);
      for (final text in tester.widgetList<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('monthly-status-cards')),
          matching: find.byType(Text),
        ),
      )) {
        expect(text.overflow, isNot(TextOverflow.ellipsis));
        expect(text.maxLines, isNull);
      }
      await capture(tester, 'android-large-200');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
