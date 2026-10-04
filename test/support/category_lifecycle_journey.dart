import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/category_selector_navigation.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/local_backup_session.dart';
import 'package:myautofinance/app/navigation/app_routes.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

/// El mismo guion para widgets y Windows/Android nativos, con archivo sintético.
Future<void> categoryLifecycleJourney(
  WidgetTester tester,
  Directory directory,
) async {
  var session = LocalBackupSession(supportDirectory: () async => directory);
  Future<T> io<T>(Future<T> Function() action) async {
    Object? error;
    StackTrace? trace;
    final result = await tester.runAsync(() async {
      try {
        return await action();
      } catch (caught, stack) {
        error = caught;
        trace = stack;
        return null;
      }
    });
    if (error != null) Error.throwWithStackTrace(error!, trace!);
    return result as T;
  }

  Future<void> settle() async {
    for (var turn = 0; turn < 300; turn++) {
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump(const Duration(milliseconds: 100));
      final loading =
          find.textContaining('Leyendo categor').evaluate().isNotEmpty ||
          find.text('Guardando categoría…').evaluate().isNotEmpty;
      if (turn >= 3 &&
          !loading &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty) {
        await tester.pumpAndSettle();
        return;
      }
    }
    fail('La interfaz no terminó su operación SQLite.');
  }

  Future<void> tap(String label) async {
    debugPrint('Recorrido categorías: $label');
    final buttons = find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate(
        (w) =>
            w is ButtonStyleButton ||
            w is PopupMenuItem ||
            w is PopupMenuButton,
      ),
    );
    final target = buttons.evaluate().isEmpty
        ? find.text(label).last
        : buttons.last;
    await tester.ensureVisible(target);
    await tester.runAsync(() => tester.tap(target));
    await settle();
  }

  NavigatorState navigator() =>
      tester.state<NavigatorState>(find.byType(Navigator).first);
  Future<CategoryManagement> management() => session.categories();
  Future<LocalDatabase> database() => session.store.open();
  Future<CategoryDetails> get(String id) =>
      io(() async => (await management()).get(id));
  Future<int> revision() =>
      io(() async => (await (await database()).readState()).revision);
  Future<Map<String, Object?>> snapshot({bool tree = true}) => io(() async {
    final db = await database();
    final result = <String, Object?>{};
    for (final table in [
      'accounts',
      'account_liquidity_periods',
      'movements',
      'budgets',
      'import_batches',
      'import_rows',
      'wealth_snapshots',
      'wealth_values',
      if (tree) 'categories',
      if (tree) 'database_state',
    ]) {
      result[table] =
          (await db.customSelect('SELECT * FROM $table ORDER BY 1').get())
              .map((row) => row.data)
              .toList();
    }
    return result;
  });
  Future<void> parent(CategoryDetails? category) async {
    await tester.ensureVisible(find.byType(OutlinedButton).first);
    await tester.tap(find.byType(OutlinedButton).first);
    await settle();
    await tap(
      category == null
          ? 'Sin padre · convertir en raíz'
          : '${category.path} · ${category.node.id}',
    );
  }

  Future<void> edit(String id) async {
    navigator().pushNamed('${AppRoutes.categories}/$id');
    await settle();
  }

  Future<void> cancel() async {
    await tap('Cancelar');
    if (find.text('Hay cambios sin guardar').evaluate().isNotEmpty) {
      await tap('Descartar cambios');
    }
  }

  Future<CategoryDetails> create(
    String name, {
    CategoryDetails? under,
    bool income = false,
  }) async {
    final before = await revision();
    await tap('Crear categoría');
    await tester.enterText(find.byType(TextField), name);
    if (under != null) {
      await parent(under);
    } else if (income) {
      await tester.ensureVisible(find.byType(DropdownButtonFormField<bool>));
      await tester.tap(find.byType(DropdownButtonFormField<bool>));
      await settle();
      await tap('Ingreso');
    }
    await tap('Crear categoría');
    expect(
      find.byType(TextField),
      findsNothing,
      reason: find
          .byType(Text)
          .evaluate()
          .map((element) => (element.widget as Text).data ?? '')
          .join('\n'),
    );
    expect(await revision(), before + 1);
    return io(
      () async => (await (await management()).list()).singleWhere(
        (item) => item.node.name == name,
      ),
    );
  }

  Future<void> move(String id, CategoryDetails? under) async {
    final before = await revision();
    await edit(id);
    await parent(under);
    expect(find.text('Tipo · solo lectura'), findsOneWidget);
    await tap('Revisar y guardar');
    await tap(under == null ? 'Convertir en raíz' : 'Trasladar rama');
    expect(await revision(), before + 1);
  }

  Future<void> archive(String id, {bool reactivate = false}) async {
    final before = await revision();
    await edit(id);
    await tap(
      reactivate ? 'Reactivar rama completa' : 'Archivar rama completa',
    );
    await tap(reactivate ? 'Reactivar rama' : 'Archivar rama');
    expect(await revision(), before + 1);
  }

  Future<void> reopen() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await io(session.store.close);
    await io(session.categoryInvalidation.close);
    session = LocalBackupSession(supportDirectory: () async => directory);
    expect(await io(session.open), isTrue);
    await tester.pumpWidget(AutofinanceApp(localSession: session));
    await settle();
    await tap('Gestión');
    await tap('Categorías');
  }

  try {
    // Mostrar el fallo de apertura original en el runner nativo, sin ocultarlo
    // tras el mensaje resumido de recuperación de la interfaz.
    await io(session.store.open);
    expect(await io(session.open), isTrue);
    await tester.pumpWidget(AutofinanceApp(localSession: session));
    await settle();
    await tap('Gestión');
    await tap('Categorías');
    final income = await create('INGRESOS', income: true);
    final expense = await create('GASTOS');
    final salary = await create('SALARIO', under: income);
    final tax = await create('IMPUESTOS', under: salary);
    final payroll = await create('NÓMINA', under: salary);
    expect(tax.node.depth, 3);
    expect(tax.node.isIncome, isTrue);

    // Puertos EP-004: no existen aún formularios financieros de otras épicas.
    await io(() async {
      final db = await database();
      final account = await SqliteAccountRepository(db).create(
        name: 'Cuenta de prueba sintética',
        kind: AccountKind.account,
        activeFrom: Month(2025, 1),
        liquidity: Liquidity.liquid,
      );
      const batch = '85000000-0000-4000-8000-000000000001';
      const origin = '85000000-0000-4000-8000-000000000002';
      await db.writeTransaction(() async {
        await db.customStatement(
          "INSERT INTO import_batches VALUES(?,?,'historical_csv','sintetico-085.csv','1','t','t','t')",
          [batch, 'a' * 64],
        );
        await db.customStatement(
          "INSERT INTO import_rows VALUES(?,?,2,'movement','t','t')",
          [origin, batch],
        );
        await SqliteMovementRepository(db).insertImported(
          MovementInput(
            accountId: account.id,
            valueDate: ValueDate(2026, 1, 5),
            concept: 'Salario bruto',
            amountCents: 300000,
            categoryId: salary.node.id,
          ),
          origin,
        );
      });
      await SqliteMovementRepository(db).create(
        MovementInput(
          accountId: account.id,
          valueDate: ValueDate(2026, 1, 6),
          concept: 'Retención',
          amountCents: -60000,
          categoryId: tax.node.id,
          discretion: 'Necesario',
        ),
      );
      final budgets = SqliteBudgetRepository(db);
      for (var month = 1; month <= 12; month++) {
        for (final entry in {
          payroll.node.id: 300000,
          tax.node.id: -60000,
        }.entries) {
          await budgets.create(
            BudgetInput(
              month: BudgetMonth(2026, month),
              categoryId: entry.key,
              amountCents: entry.value,
              concept: 'Previsión sintética',
              discretion: 'Necesario',
            ),
          );
        }
      }
      await db.writeTransaction(() async {
        await db.customStatement(
          "INSERT INTO wealth_snapshots VALUES(?,'2026-01-01','t','t')",
          ['85000000-0000-4000-8000-000000000003'],
        );
        await db.customStatement(
          "INSERT INTO wealth_values VALUES(?,?,?,900000,'t','t')",
          [
            '85000000-0000-4000-8000-000000000004',
            '85000000-0000-4000-8000-000000000003',
            account.id,
          ],
        );
      });
    });
    final history = await snapshot(tree: false);
    final categoryIds = await io(
      () async => (await (await management()).list())
          .map((item) => item.node.id)
          .toSet(),
    );
    Future<void> figures(
      String root, {
      required bool isIncome,
      required String path,
    }) async {
      await io(() async {
        final db = await database();
        final movements = await SqliteMovementRepository(db)
            .readYear(2026, categoryId: root);
        expect(movements.length, 2);
        expect(movements.map((row) => row.id).toSet().length, 2);
        expect(
          movements.fold(0, (sum, row) => sum + row.data.amountCents),
          240000,
        );
        final budgets = await SqliteBudgetRepository(db).readYear(2026);
        expect(budgets.length, 24);
        expect(
          budgets.fold(0, (sum, row) => sum + row.data.amountCents),
          2880000,
        );
        expect(
          (await SqliteBudgetRepository(
            db,
          ).readYear(2026, incomeOnly: true)).length,
          isIncome ? 24 : 0,
        );
        final tree = CategoryGrouping(await (await management()).list());
        expect(tree.categories[tax.node.id]!.path, path);
        expect(tree.categories[tax.node.id]!.node.isIncome, isIncome);
        final direct = <String, int>{};
        for (final row in movements) {
          direct.update(
            row.data.categoryId!,
            (value) => value + row.data.amountCents,
            ifAbsent: () => row.data.amountCents,
          );
        }
        final totals = tree.aggregate(direct);
        expect(totals[root], 240000);
        expect(totals[tax.node.id], -60000);
      });
      expect(await snapshot(tree: false), history);
      expect(
        await io(
          () async => (await (await management()).list())
              .map((item) => item.node.id)
              .toSet(),
        ),
        categoryIds,
      );
    }

    await figures(income.node.id, isIncome: true, path: tax.path);
    var unchanged = await snapshot();
    await edit(income.node.id);
    expect(find.byType(DropdownButtonFormField<bool>), findsNothing);
    expect(find.textContaining('Tipo bloqueado:'), findsOneWidget);
    await io(
      () async => expectLater(
        (await management()).edit(
          income.node.id,
          name: 'NO GUARDAR',
          parentId: null,
          isIncome: false,
        ),
        throwsA(isA<CategoryFailure>()),
      ),
    );
    await cancel();
    expect(await snapshot(), unchanged);
    await edit(income.node.id);
    await parent(tax);
    await tap('Revisar y guardar');
    expect(find.textContaining('crearía un ciclo'), findsWidgets);
    await cancel();
    expect(await snapshot(), unchanged);
    await tap('Crear categoría');
    await tester.enterText(find.byType(TextField), 'CUARTO NIVEL');
    await parent(tax);
    await tap('Crear categoría');
    expect(find.textContaining('superaría tres niveles'), findsWidgets);
    await cancel();
    expect(await snapshot(), unchanged);
    await edit(income.node.id);
    await parent(expense);
    await tap('Revisar y guardar');
    expect(find.textContaining('superaría tres niveles'), findsWidgets);
    await cancel();
    expect(await snapshot(), unchanged);
    await edit(tax.node.id);
    await tester.enterText(find.byType(TextField), 'NO GUARDAR');
    await cancel();
    expect(await snapshot(), unchanged);
    await edit(salary.node.id);
    await parent(expense);
    await tap('Revisar y guardar');
    await tap('Cancelar');
    expect(find.text('Editar categoría'), findsOneWidget);
    await cancel();
    expect(await snapshot(), unchanged);

    await edit(tax.node.id);
    await tester.enterText(find.byType(TextField), 'RETENCIONES');
    final beforeRename = await revision();
    await tap('Revisar y guardar');
    expect(await revision(), beforeRename + 1);
    await figures(
      income.node.id,
      isIncome: true,
      path: 'INGRESOS / SALARIO / RETENCIONES',
    );
    await move(salary.node.id, expense);
    await figures(
      expense.node.id,
      isIncome: false,
      path: 'GASTOS / SALARIO / RETENCIONES',
    );
    expect(
      await io(
        () async =>
            SqliteMovementRepository(await database())
                .readYear(2026, categoryId: income.node.id),
      ),
      isEmpty,
    );
    await move(salary.node.id, null);
    expect((await get(salary.node.id)).node.isIncome, isFalse);
    await figures(
      salary.node.id,
      isIncome: false,
      path: 'SALARIO / RETENCIONES',
    );
    await move(salary.node.id, income);
    await figures(
      income.node.id,
      isIncome: true,
      path: 'INGRESOS / SALARIO / RETENCIONES',
    );
    await move(salary.node.id, null);
    expect((await get(salary.node.id)).node.isIncome, isTrue);
    await figures(
      salary.node.id,
      isIncome: true,
      path: 'SALARIO / RETENCIONES',
    );
    await archive(salary.node.id);
    for (final item in [salary, tax, payroll]) {
      expect((await get(item.node.id)).node.archived, isTrue);
    }
    await figures(
      salary.node.id,
      isIncome: true,
      path: 'SALARIO / RETENCIONES',
    );
    unchanged = await snapshot();
    await io(() async {
      final db = await database();
      final movements = SqliteMovementRepository(db);
      final original = (await movements.readYear(2026)).first;
      await expectLater(
        movements.create(
          MovementInput(
            accountId: original.data.accountId,
            valueDate: ValueDate(2026, 2, 1),
            concept: 'Nueva asignación prohibida',
            amountCents: 1,
            categoryId: tax.node.id,
          ),
        ),
        throwsA(isA<MovementFailure>()),
      );
      await expectLater(
        SqliteBudgetRepository(db).create(
          BudgetInput(
            month: BudgetMonth(2027, 1),
            categoryId: tax.node.id,
            amountCents: 0,
          ),
        ),
        throwsA(isA<BudgetFailure>()),
      );
      expect(
        (await (await management()).assignmentOptions()).map(
          (item) => item.node.id,
        ),
        isNot(contains(tax.node.id)),
      );
    });
    expect(await snapshot(), unchanged);
    final archivedTax = await get(tax.node.id);
    navigator().push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _SyntheticConsumer(session: session, selected: archivedTax),
      ),
    );
    await settle();
    await tap('Elegir categoría');
    expect(
      find.text('Selección: SALARIO / RETENCIONES · Archivada · Ingreso'),
      findsOneWidget,
    );
    expect(find.text('SALARIO / RETENCIONES'), findsNothing);
    await tap('Cancelar');
    navigator().pop();
    await settle();
    expect(await snapshot(), unchanged);
    await reopen();
    expect(await snapshot(), unchanged);
    await figures(
      salary.node.id,
      isIncome: true,
      path: 'SALARIO / RETENCIONES',
    );
    await archive(salary.node.id, reactivate: true);
    for (final item in [salary, tax, payroll]) {
      expect((await get(item.node.id)).node.archived, isFalse);
    }
    await figures(
      salary.node.id,
      isIncome: true,
      path: 'SALARIO / RETENCIONES',
    );
    await io(() async {
      final budgets = SqliteBudgetRepository(await database());
      for (final entry in {tax.node.id: -60000, expense.node.id: 0}.entries) {
        await budgets.create(
          BudgetInput(
            month: BudgetMonth(2025, 1),
            categoryId: entry.key,
            amountCents: entry.value,
          ),
        );
      }
    });
    unchanged = await snapshot();
    final generation = session.categoryInvalidation.generation;
    await edit(salary.node.id);
    await tester.enterText(
      find.byType(TextField),
      'RENOMBRE PARCIAL PROHIBIDO',
    );
    await parent(expense);
    await tap('Revisar y guardar');
    await tap('Trasladar rama');
    expect(find.textContaining('enero de 2025'), findsWidgets);
    expect(find.textContaining(tax.node.id), findsWidgets);
    expect(find.textContaining(expense.node.id), findsWidgets);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'RENOMBRE PARCIAL PROHIBIDO',
    );
    expect(await snapshot(), unchanged);
    expect(session.categoryInvalidation.generation, generation);
    await cancel();
    await reopen();
    expect(await snapshot(), unchanged);

    final originKey = GlobalKey<_SyntheticConsumerState>();
    final selectedTax = await get(tax.node.id);
    navigator().push(
      MaterialPageRoute<void>(
        builder: (_) => _SyntheticConsumer(
          key: originKey,
          session: session,
          selected: selectedTax,
        ),
      ),
    );
    await settle();
    await tester.enterText(
      find.byKey(const ValueKey('consumer-draft')),
      'Concepto pendiente',
    );
    final originState = originKey.currentState!;
    final selectorRevision = await revision();
    await tap('Elegir categoría');
    expect(
      find.text('Selección: SALARIO / RETENCIONES · Ingreso'),
      findsOneWidget,
    );
    await tap('Crear categoría');
    await tester.enterText(find.byType(TextField), 'NO CREAR');
    await cancel();
    expect(
      find.text('Selección: SALARIO / RETENCIONES · Ingreso'),
      findsOneWidget,
    );
    await tap('Cancelar');
    expect(originKey.currentState, same(originState));
    expect(originState.selected.node.id, tax.node.id);
    expect(originState.draft.text, 'Concepto pendiente');
    expect(find.text('enero 2026 · filtro pendiente'), findsOneWidget);
    expect(await revision(), selectorRevision);
    await tap('Elegir categoría');
    await tap('Crear categoría');
    await tester.enterText(find.byType(TextField), 'BONUS SINTÉTICO');
    await parent(income);
    await tap('Crear categoría');
    expect(
      find.text('Selección: INGRESOS / BONUS SINTÉTICO · Ingreso'),
      findsOneWidget,
    );
    await tap('Seleccionar');
    expect(originKey.currentState, same(originState));
    expect(originState.selected.path, 'INGRESOS / BONUS SINTÉTICO');
    expect(originState.selected.node.id, isNot(tax.node.id));
    expect(originState.draft.text, 'Concepto pendiente');
    expect(await revision(), selectorRevision + 1);
    final finalState = await snapshot();
    await reopen();
    expect(await snapshot(), finalState);
    expect(
      (await io(
        () async => SqliteMovementRepository(await database()).readYear(2026),
      )).length,
      2,
    );
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await io(session.store.close);
    await io(session.categoryInvalidation.close);
  }
}

// Consumidor de prueba; no implementa una pantalla de otra épica.
class _SyntheticConsumer extends StatefulWidget {
  const _SyntheticConsumer({
    super.key,
    required this.session,
    required this.selected,
  });
  final LocalBackupSession session;
  final CategoryDetails selected;
  @override
  State<_SyntheticConsumer> createState() => _SyntheticConsumerState();
}

class _SyntheticConsumerState extends State<_SyntheticConsumer> {
  final draft = TextEditingController();
  late CategoryDetails selected = widget.selected;
  @override
  void dispose() {
    draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          const Text('enero 2026 · filtro pendiente'),
          TextField(key: const ValueKey('consumer-draft'), controller: draft),
          Text(selected.path),
          FilledButton(
            onPressed: () async {
              final result = await selectCategory(
                context,
                loadManagement: widget.session.categories,
                selectedId: selected.node.id,
              );
              if (mounted && result != null) setState(() => selected = result);
            },
            child: const Text('Elegir categoría'),
          ),
        ],
      ),
    ),
  );
}
