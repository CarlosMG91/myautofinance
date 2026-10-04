import 'dart:async' show Completer;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/category_selector_navigation.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/navigation/app_router.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/movements/presentation/category_selector.dart';
import 'package:myautofinance/features/movements/presentation/category_tree_screen.dart';

void main() {
  late LocalDatabase db;
  late CategoryReadInvalidation invalidation;
  late CategoryManagement service;
  setUp(() {
    db = LocalDatabase(
      NativeDatabase.memory(
        setup: (sqlite) => sqlite.execute('PRAGMA foreign_keys=ON'),
      ),
    );
    invalidation = CategoryReadInvalidation();
    service = createCategoryManagement(
      database: db,
      invalidation: invalidation,
    );
  });
  tearDown(() async {
    await invalidation.close();
    await db.close();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('UUID y ruta; duplicados; cancelar no aplica el borrador', (
    tester,
  ) async {
    final first = (await tester.runAsync(
      () => service.create(name: 'Duplicada', isIncome: false),
    ))!;
    final second = (await tester.runAsync(
      () => service.create(name: 'Duplicada', isIncome: true),
    ))!;
    CategoryDetails? result;
    var returned = false;
    await tester.pumpWidget(
      MaterialApp(
        home: CategorySelector(
          loadManagement: () async => service,
          selectedId: first.node.id,
          onCreate: () async => null,
          onReturn: (value) {
            result = value;
            returned = true;
          },
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Ingreso · ${second.node.id}'));
    await tester.pump();
    await tester.tap(find.text('Cancelar'));
    expect(returned, isTrue);
    expect(result, isNull);
    await tester.tap(find.text('Seleccionar'));
    expect(result!.node.id, second.node.id);
    expect(result!.path, 'Duplicada');
    expect(result!.node.isIncome, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(result, isNull);
  });

  testWidgets(
    'Archivada histórica visible; opciones activas y actualización de ruta/tipo',
    (tester) async {
      final root = (await tester.runAsync(
        () => service.create(name: 'Ingreso', isIncome: true),
      ))!;
      final child = (await tester.runAsync(
        () => service.create(name: 'Hoja', parentId: root.node.id),
      ))!;
      final target = (await tester.runAsync(
        () => service.create(name: 'Gastos', isIncome: false),
      ))!;
      await tester.runAsync(() => service.archive(root.node.id));
      CategoryDetails? result;
      await tester.pumpWidget(
        MaterialApp(
          home: CategorySelector(
            loadManagement: () async => service,
            selectedId: child.node.id,
            onCreate: () async => null,
            onReturn: (value) => result = value,
          ),
        ),
      );
      await settle(tester);
      expect(
        find.text('Selección: Ingreso / Hoja · Archivada · Ingreso'),
        findsOneWidget,
      );
      expect(find.text('Ingreso / Hoja'), findsNothing);
      await tester.runAsync(() async {
        final other = createCategoryManagement(
          database: db,
          invalidation: invalidation,
        );
        await other.move(root.node.id, parentId: target.node.id);
        await other.rename(target.node.id, name: 'Salidas');
      });
      await settle(tester);
      expect(
        find.text('Selección: Salidas / Ingreso / Hoja · Archivada · Salida'),
        findsOneWidget,
      );
      await tester.tap(find.text('Seleccionar'));
      expect(result!.path, 'Salidas / Ingreso / Hoja');
      expect(result!.node.archived, isTrue);
      expect(result!.node.isIncome, isFalse);
      await tester.runAsync(() => service.reactivate(root.node.id));
      await settle(tester);
      expect(find.text('Salidas / Ingreso / Hoja'), findsOneWidget);
    },
  );

  testWidgets(
    'Alta real vuelve al selector con el UUID nuevo; cancelar alta conserva anterior',
    (tester) async {
      final original = (await tester.runAsync(
        () => service.create(name: 'Anterior', isIncome: false),
      ))!;
      CategoryDetails? applied;
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          onGenerateRoute: (settings) => AppRouter.generateRoute(
            settings,
            categories: () async => service,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  final result = await selectCategory(
                    context,
                    loadManagement: () async => service,
                    selectedId: original.node.id,
                  );
                  if (result != null) applied = result;
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await settle(tester);
      await tester.tap(find.text('Crear categoría'));
      await settle(tester);
      await tester.tap(find.text('Cancelar').last);
      await settle(tester);
      expect(find.text('Selección: Anterior · Salida'), findsOneWidget);
      await tester.tap(find.text('Crear categoría'));
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, 'Nueva sintética');
      await tester.tap(find.widgetWithText(FilledButton, 'Crear categoría'));
      await settle(tester);
      expect(find.text('Selección: Nueva sintética · Salida'), findsOneWidget);
      await tester.tap(find.text('Seleccionar'));
      await settle(tester);
      expect(applied!.path, 'Nueva sintética');
      expect(applied!.node.id, isNot(original.node.id));
      final stored = await tester.runAsync(() => service.get(applied!.node.id));
      expect(stored!.path, applied!.path);
      expect(find.text('Abrir'), findsOneWidget);
      await tester.tap(find.text('Abrir'));
      await settle(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(applied!.path, 'Nueva sintética');
      expect(find.text('Abrir'), findsOneWidget);
    },
  );

  testWidgets('Error y reintento no permiten confirmar datos obsoletos', (
    tester,
  ) async {
    final root = (await tester.runAsync(
      () => service.create(name: 'Primera', isIncome: false),
    ))!;
    var failing = true;
    Future<CategoryManagement> load() async {
      if (failing) throw const CategoryFailure('Error sintético');
      return service;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: CategorySelector(
          loadManagement: load,
          selectedId: root.node.id,
          onCreate: () async => null,
          onReturn: (_) {},
        ),
      ),
    );
    await settle(tester);
    expect(find.text('Error sintético'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    failing = false;
    await tester.tap(find.text('Reintentar'));
    await settle(tester);
    expect(find.text('Selección: Primera · Salida'), findsOneWidget);
  });

  testWidgets(
    'Invalidaciones durante carga descartan respuestas y errores anteriores',
    (tester) async {
      final root = (await tester.runAsync(
        () => service.create(name: 'Inicial', isIncome: false),
      ))!;
      final delayed = Completer<CategoryManagement>();
      var delayNext = false;
      Future<CategoryManagement> load() {
        if (delayNext) {
          delayNext = false;
          return delayed.future;
        }
        return Future.value(service);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: CategorySelector(
            loadManagement: load,
            selectedId: root.node.id,
            onReturn: (_) {},
            onCreate: () async => null,
          ),
        ),
      );
      await settle(tester);
      delayNext = true;
      await tester.runAsync(
        () => service.rename(root.node.id, name: 'Intermedia'),
      );
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.runAsync(() => service.rename(root.node.id, name: 'Última'));
      await settle(tester);
      expect(find.text('Selección: Última · Salida'), findsOneWidget);
      delayed.completeError(
        const CategoryFailure('Error de una carga anterior'),
      );
      await settle(tester);
      expect(find.text('Error de una carga anterior'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    },
  );

  for (final width in [320.0, 412.0, 1440.0]) {
    testWidgets('Selector $width px, texto 200 %, sin overflow', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(
        () => service.create(
          name:
              'Ruta sintética suficientemente larga para ocupar varias líneas',
          isIncome: false,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: CategorySelector(
            loadManagement: () async => service,
            onReturn: (_) {},
            onCreate: () async => null,
          ),
        ),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Crear categoría'), findsOneWidget);
    });
  }

  testWidgets('Árbol abierto se actualiza tras escritura de otro servicio', (
    tester,
  ) async {
    final root = (await tester.runAsync(
      () => service.create(name: 'Antes', isIncome: false),
    ))!;
    await tester.pumpWidget(
      MaterialApp(
        home: CategoryTreeScreen(
          loadManagement: () async => service,
          onOpenEditor: (_) async => null,
          onReturn: () {},
          returnLabel: 'Volver',
        ),
      ),
    );
    await settle(tester);
    final other = createCategoryManagement(
      database: db,
      invalidation: invalidation,
    );
    await tester.runAsync(() => other.rename(root.node.id, name: 'Después'));
    await settle(tester);
    expect(find.text('Después'), findsWidgets);
    expect(find.text('Antes'), findsNothing);
  });
}
