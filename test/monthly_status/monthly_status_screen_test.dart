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
import 'package:myautofinance/app/navigation/app_router.dart';
import 'package:myautofinance/app/navigation/monthly_status_origin.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/monthly_status/monthly_status.dart';
import 'package:myautofinance/features/monthly_status/presentation/monthly_status_screen.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

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
  var loads = 0;

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

  Future<void> backToStatus(WidgetTester tester) =>
      tap(tester, find.byTooltip('Volver a Estado del mes, 01/2026'));

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('STATUS_CAPTURE')) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('status-capture')),
      );
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('.tools/160-$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<MonthlyStatusQuery> load() async {
    loads++;
    return createMonthlyStatusQuery(database: db, invalidation: invalidation);
  }

  Future<void> boot(
    WidgetTester tester, {
    double width = 1440,
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
    loads = 0;
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

  testWidgets(
    'tabla SQLite, tres niveles, padre no prorrateado, cero y detalle directo/rama',
    (tester) async {
      await boot(tester);
      expect(
        find.byKey(const ValueKey('monthly-status-table')),
        findsOneWidget,
      );
      expect(find.text('Supermercado'), findsNothing);
      expect(find.text('−400,00 €'), findsNWidgets(3)); // resumen, raíz, total
      expect(find.text('−351,25 €'), findsNWidgets(3));
      expect(find.text('0,00 € (registrado)'), findsOneWidget);
      expect(find.text('Sin presupuesto'), findsNWidgets(2));
      await capture(tester, 'windows');
      await tap(tester, find.byKey(ValueKey('$root:expandir')));
      await tap(tester, find.byKey(ValueKey('$child:expandir')));
      expect(find.text('Compra semanal'), findsOneWidget);
      await capture(tester, 'windows-expandido');
      expect(
        find.widgetWithText(TextButton, 'Sin presupuesto'),
        findsNWidgets(4),
      );
      await tap(tester, find.byKey(ValueKey('$root:directo')));
      expect(
        find.text(
          'No hay movimientos que coincidan con este periodo y filtros.',
        ),
        findsOneWidget,
      );
      await backToStatus(tester);
      expect(find.text('Compra semanal'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, '$root:directo');
      await tap(tester, find.byKey(ValueKey('$root:real')));
      expect(find.text('Movimiento sintético'), findsOneWidget);
      await backToStatus(tester);
      await tap(tester, find.byKey(ValueKey('$empty:real')));
      expect(
        find.text('Movimiento sintético'),
        findsNWidgets(2),
      ); // neto cero mantiene fuentes
    },
  );

  testWidgets(
    'diferencia ofrece fuentes, Escape vuelve y conserva expansión/scroll/foco',
    (tester) async {
      await boot(tester);
      await tap(tester, find.byKey(ValueKey('$root:expandir')));
      await tap(tester, find.byKey(ValueKey('$child:expandir')));
      await tap(tester, find.byKey(ValueKey('$leaf:diferencia')));
      final offset = session.context.scrollOffset;
      expect(find.text('Origen de la diferencia'), findsOneWidget);
      expect(find.text('Ver movimientos reales'), findsOneWidget);
      expect(find.text('Ver partidas previstas'), findsOneWidget);
      await capture(tester, 'diferencia');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.text('Origen de la diferencia'), findsNothing);
      expect(find.text('Compra semanal'), findsOneWidget);
      expect(session.context.filters['abiertas'], contains(child));
      expect(session.context.scrollOffset, closeTo(offset, 1));
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        '$leaf:diferencia',
      );
      await tap(tester, find.byKey(ValueKey('$root:previsto')));
      expect(find.text('Alimentación'), findsWidgets);
      expect(
        find.text('Compra semanal'),
        findsNothing,
      ); // partida original padre
    },
  );

  testWidgets(
    'cambiar mes oculta cifras anteriores y descarta loader tardío, error reintentable',
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
      expect(find.byKey(const ValueKey('monthly-status-table')), findsNothing);
      await tap(tester, find.text('Reintentar'));
      expect(
        find.text('No hay movimientos en este mes. Real: 0,00 €.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'volver de alta y Gestión refresca, invalidación relee catálogo y conserva ramas',
    (tester) async {
      await boot(tester);
      await tap(tester, find.byKey(ValueKey('$root:expandir')));
      await tap(tester, find.byKey(const ValueKey('status-add')));
      expect(find.text('Fecha de valor · AAAA-MM-DD'), findsOneWidget);
      expect(find.text('Guardar movimiento'), findsOneWidget);
      await real(root, 500);
      await tap(tester, find.text('Volver al origen'));
      expect(find.text('−346,25 €'), findsNWidgets(3));
      expect(find.text('Supermercado'), findsOneWidget);
      final before = loads;
      await tap(tester, find.text('Gestión'));
      await tap(tester, find.text('Categorías'));
      final hiddenReads = loads;
      await tester.runAsync(
        () => categories.edit(
          root,
          name: 'Alimentación actual',
          parentId: null,
          isIncome: false,
        ),
      );
      await settle(tester);
      expect(loads, hiddenReads);
      await tap(tester, find.text('Volver a Estado del mes, enero de 2026'));
      expect(loads, greaterThan(before));
      expect(find.text('Alimentación actual'), findsOneWidget);
      await tester.runAsync(
        () => categories.edit(
          root,
          name: 'Comida',
          parentId: null,
          isIncome: false,
        ),
      );
      await settle(tester);
      expect(find.text('Comida'), findsOneWidget);
      expect(find.text('Supermercado'), findsOneWidget);
    },
  );

  testWidgets(
    'Windows estrecho y texto 200% usa tarjetas sin perder cifras ni expansión',
    (tester) async {
      await boot(tester, width: 320, scale: 2);
      expect(
        find.byKey(const ValueKey('monthly-status-cards')),
        findsOneWidget,
      );
      await tap(tester, find.byKey(ValueKey('$root:expandir')));
      await capture(tester, 'estrecho-200');
      await tap(tester, find.byKey(ValueKey('$child:expandir')));
      expect(find.textContaining('Compra semanal'), findsOneWidget);
      expect(find.text('Real directo'), findsNWidgets(7));
      tester.view.physicalSize = const Size(1440, 900);
      await settle(tester);
      expect(find.textContaining('Compra semanal'), findsOneWidget);
      await tap(tester, find.byKey(ValueKey('$leaf:real')));
      expect(find.textContaining('Movimiento sintético'), findsWidgets);
    },
  );

  testWidgets(
    'editar real y presupuesto desde cifras refresca Estado al volver',
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
      await tap(tester, find.text('Volver al origen'));
      expect(find.text('−450,00 €'), findsNWidgets(3));
      await tap(tester, find.byKey(ValueKey('$root:real')));
      await tap(tester, find.text('Abrir Movimiento sintético'));
      await tap(tester, find.text('Editar'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Importe firmado (EUR)'),
        '-360,25',
      );
      await tap(tester, find.text('Guardar movimiento'));
      await backToStatus(tester);
      expect(find.text('−361,25 €'), findsNWidgets(3));
      expect(find.text('+88,75 €\nA favor'), findsNWidgets(2));
    },
  );

  testWidgets('total y Sin clasificar abren sus fuentes una sola vez', (
    tester,
  ) async {
    await boot(tester);
    await tap(tester, find.byKey(const ValueKey('sin-clasificar:real')));
    expect(find.text('Movimiento sintético'), findsOneWidget);
    expect(find.text('−1,00 €'), findsOneWidget);
    await backToStatus(tester);
    await tap(tester, find.byKey(const ValueKey('total:real')));
    expect(find.text('Movimiento sintético'), findsNWidgets(4));
    await backToStatus(tester);
    await tap(tester, find.byKey(const ValueKey('total:diferencia')));
    await tap(tester, find.text('Ver partidas previstas'));
    expect(find.text('Abrir'), findsNWidgets(2));
    expect(find.text('0,00 € (registrado)'), findsOneWidget);
    await tap(tester, find.text('Volver al origen'));
    await tap(tester, find.byKey(const ValueKey('sin-clasificar:previsto')));
    expect(
      find.textContaining('Sin presupuesto · No hay partidas'),
      findsOneWidget,
    );
  });

  testWidgets(
    'recarga del mismo mes conserva scroll real y foco con filas largas',
    (tester) async {
      for (var i = 0; i < 18; i++) {
        await categories.create(name: 'A rama $i', isIncome: false);
      }
      await boot(tester);
      await tap(tester, find.byKey(ValueKey('$root:expandir')));
      await tap(tester, find.byKey(ValueKey('$child:expandir')));
      await tap(tester, find.byKey(ValueKey('$leaf:diferencia')));
      final saved = session.context.scrollOffset;
      expect(saved, greaterThan(300));
      await tap(tester, find.text('Cancelar'));
      expect(session.context.scrollOffset, closeTo(saved, 1));
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        '$leaf:diferencia',
      );
      expect(find.text('Compra semanal'), findsOneWidget);
      await tester.runAsync(
        () => categories.edit(
          leaf,
          name: 'Compra actual',
          parentId: child,
          isIncome: null,
        ),
      );
      await settle(tester);
      expect(session.context.scrollOffset, closeTo(saved, 1));
      expect(find.text('Compra actual'), findsOneWidget);
    },
  );

  testWidgets('UUID, traslado y archivo mantienen datos y árbol actual', (
    tester,
  ) async {
    final other = (await categories.create(
      name: 'Nueva raíz',
      isIncome: false,
    )).node.id;
    await categories.create(name: 'Compra semanal', parentId: child);
    await boot(tester);
    await tap(tester, find.byKey(ValueKey('$root:expandir')));
    await tap(tester, find.byKey(ValueKey('$child:expandir')));
    expect(
      find.text('Compra semanal'),
      findsOneWidget,
    ); // homónimo sin datos excluido
    await tester.runAsync(
      () => categories.edit(
        child,
        name: 'Supermercado actual',
        parentId: other,
        isIncome: null,
      ),
    );
    await settle(tester);
    expect(find.text('Compra semanal'), findsNothing);
    await tap(tester, find.byKey(ValueKey('$other:expandir')));
    expect(find.text('Compra semanal'), findsOneWidget);
    expect(find.text('Supermercado actual'), findsOneWidget);
    await tester.runAsync(() => categories.archive(child));
    await settle(tester);
    expect(find.text('Compra semanal · Archivada'), findsOneWidget);
    await tap(tester, find.byKey(ValueKey('$leaf:real')));
    expect(find.text('Movimiento sintético'), findsOneWidget);
  });

  testWidgets(
    'invalidación de restauración resuelve la conexión activa nueva',
    (tester) async {
      LocalDatabase active = db;
      final replacement = LocalDatabase(
        NativeDatabase.memory(setup: configureConnection),
      );
      addTearDown(replacement.close);
      final newCategories = createCategoryManagement(
        database: replacement,
        invalidation: invalidation,
      );
      final newRoot = (await newCategories.create(
        name: 'Raíz restaurada',
        isIncome: true,
      )).node.id;
      await SqliteBudgetRepository(replacement).create(
        BudgetInput(month: jan, categoryId: newRoot, amountCents: 77700),
      );
      await boot(
        tester,
        loader: () async => createMonthlyStatusQuery(
          database: active,
          invalidation: invalidation,
        ),
      );
      expect(find.text('−351,25 €'), findsNWidgets(3));
      active = replacement;
      invalidation.invalidate();
      await settle(tester);
      expect(find.text('Alimentación'), findsNothing);
      expect(find.text('Raíz restaurada'), findsOneWidget);
      expect(find.text('+777,00 €'), findsNWidgets(3));
      expect(
        find.text('No hay movimientos en este mes. Real: 0,00 €.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('ruta sin pila recupera ramas, posición y foco serializados', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final origin = MonthlyStatusOrigin(
      NavigationContext(
        destination: SessionDestination.status,
        period: NavigationPeriod(2026, 1),
        branchId: leaf,
        filters: {'abiertas': '$root,$child'},
        focus: '$leaf:real',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: (settings) => AppRouter.generateRoute(
          settings,
          monthlyStatus: load,
          navigationSession: session,
        ),
        onGenerateInitialRoutes: (_) => [
          AppRouter.generateRoute(
            RouteSettings(name: origin.route),
            monthlyStatus: load,
            navigationSession: session,
          ),
        ],
      ),
    );
    await settle(tester);
    expect(find.text('Compra semanal'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, '$leaf:real');
    expect(session.context.filters['abiertas'], '$root,$child');
  });

  testWidgets('totales EP-001 B/C: enero y febrero, sin fotos patrimoniales', (
    tester,
  ) async {
    final income = (await categories.create(
      name: 'Ingresos',
      isIncome: true,
    )).node.id;
    final rent = (await categories.create(
      name: 'Vivienda',
      isIncome: false,
    )).node.id;
    final saving = (await categories.create(
      name: 'Ahorro',
      isIncome: false,
    )).node.id;
    await budgets.create(
      BudgetInput(month: jan, categoryId: income, amountCents: 300000),
    );
    await budgets.create(
      BudgetInput(month: jan, categoryId: rent, amountCents: -100000),
    );
    await budgets.create(
      BudgetInput(month: jan, categoryId: saving, amountCents: -50000),
    );
    await real(income, 310000);
    await real(rent, -100000);
    await real(saving, -50000);
    await real(empty, -1000);
    await real(empty, -1000);
    await real(null, 100); // compensa la fuente sintética inicial sin ocultarla
    final feb = BudgetMonth(2026, 2);
    for (final (category, planned, actual) in [
      (income, 300000, 302000),
      (rent, -100000, -100000),
      (saving, -50000, -50000),
      (leaf, -40000, -42010),
    ]) {
      await budgets.create(
        BudgetInput(month: feb, categoryId: category, amountCents: planned),
      );
      await movements.create(
        MovementInput(
          accountId: account,
          valueDate: ValueDate(2026, 2, 9),
          concept: 'Febrero sintético',
          amountCents: actual,
          categoryId: category,
        ),
      );
    }
    await boot(tester);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('total:previsto')),
        matching: find.text('+1.100,00 €'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('total:real')),
        matching: find.text('+1.229,75 €'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('total:diferencia')),
        matching: find.text('+129,75 €\nA favor'),
      ),
      findsOneWidget,
    );
    await session.selectPeriod(NavigationPeriod(2026, 2));
    await settle(tester);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('total:real')),
        matching: find.text('+1.099,90 €'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('total:diferencia')),
        matching: find.text('−0,10 €\nEn contra'),
      ),
      findsOneWidget,
    );
  });
}
