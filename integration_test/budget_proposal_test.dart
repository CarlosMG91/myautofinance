import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:myautofinance/app/budget_factory.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/navigation/app_router.dart';
import 'package:myautofinance/app/regional.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'EP-018 propuesta, cancelación, sustitución y reapertura SQLite nativa',
    (tester) async {
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      final support = await getApplicationSupportDirectory();
      final fixtures = await Directory(
        p.join(support.path, 'proposal-synthetic-tests'),
      ).create(recursive: true);
      final fixtureRoot = await fixtures.resolveSymbolicLinks();
      final temporary = await fixtures.createTemp('ma-tsk-154-');
      final directory = Directory(await temporary.resolveSymbolicLinks());
      if (!p.isWithin(fixtureRoot, directory.path)) {
        throw StateError(
          'La carpeta sintética queda fuera del ámbito de pruebas.',
        );
      }
      final file = File(p.join(directory.path, 'synthetic.sqlite'));
      LocalDatabase open() => LocalDatabase(
        NativeDatabase(
          file,
          setup: (sqlite) => sqlite.execute('PRAGMA foreign_keys=ON'),
        ),
      );
      var db = open();
      final invalidation = CategoryReadInvalidation();
      Future<void> settle() async {
        for (var i = 0; i < 15; i++) {
          await tester.runAsync(() async {
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 20));
          });
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.runAsync(() => tester.tap(finder));
        await settle();
      }

      try {
        final categories = createCategoryManagement(
          database: db,
          invalidation: invalidation,
        );
        final root = (await categories.create(name: 'Alimentación')).node.id;
        final child = (await categories.create(
          name: 'Supermercado',
          parentId: root,
        )).node.id;
        final account = (await SqliteAccountRepository(db).create(
          name: 'Cuenta sintética',
          kind: AccountKind.account,
          activeFrom: Month(2026, 1),
          liquidity: Liquidity.liquid,
        )).id;
        await SqliteMovementRepository(db).create(
          MovementInput(
            accountId: account,
            valueDate: ValueDate(2026, 1, 15),
            categoryId: child,
            concept: 'Real sintético',
            amountCents: -35025,
          ),
        );
        final budgets = SqliteBudgetRepository(db);
        final prior = await budgets.create(
          BudgetInput(
            month: BudgetMonth(2027, 1),
            categoryId: root,
            amountCents: -50000,
          ),
        );
        final original = await budgets.create(
          BudgetInput(
            month: BudgetMonth(2026, 1),
            categoryId: child,
            amountCents: -10000,
          ),
        );
        final source = createBudgetSource(db, invalidation);
        await tester.pumpWidget(
          MaterialApp(
            locale: AppRegional.locale,
            supportedLocales: AppRegional.supportedLocales,
            localizationsDelegates: AppRegional.delegates,
            onGenerateInitialRoutes: (_) => [
              AppRouter.generateRoute(
                const RouteSettings(name: '/presupuesto?a=2026&m=01'),
                budgets: () async => source,
              ),
            ],
            onGenerateRoute: (settings) =>
                AppRouter.generateRoute(settings, budgets: () async => source),
          ),
        );
        await settle();
        await tap(find.text('Proponer año siguiente'));
        await tap(find.text('Generar propuesta'));
        if (!Platform.isWindows) {
          await tap(find.text('Alimentación'));
          await tap(find.text('Enero'));
        }
        final edit = find.byKey(ValueKey('edit-$root-2027-01-01'));
        await tap(edit);
        await tester.enterText(
          find.widgetWithText(TextField, 'Importe propuesto'),
          '-370',
        );
        if (Platform.isWindows) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await settle();
        } else {
          await tap(find.text('Aplicar importe'));
        }
        await tap(find.byKey(ValueKey('split-$root-2027-01-01')));
        await tap(find.byKey(ValueKey('split-option-$child')));
        await tester.enterText(
          find.widgetWithText(
            TextField,
            'Importe de Alimentación / Supermercado',
          ),
          '-370',
        );
        await tap(find.text('Aplicar desglose'));
        await tap(find.text('Revisar y guardar'));
        expect(find.textContaining('Alimentación · Retirada'), findsOneWidget);
        if (Platform.isWindows) {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await settle();
        } else {
          await tester.binding.handlePopRoute();
          await settle();
        }
        expect(find.byKey(ValueKey('edit-$child-2027-01-01')), findsOneWidget);
        expect((await budgets.get(prior.id))!.data.amountCents, -50000);
        await tap(find.text('Revisar y guardar'));
        await tap(
          find.widgetWithText(
            CheckboxListTile,
            'He revisado la comparación y confirmo «Sustituir partidas»',
          ),
        );
        await tap(find.widgetWithText(FilledButton, 'Sustituir partidas'));
        expect(find.text('Propuesta guardada en 2027'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await settle();
        await db.close();
        db = open();
        final reopened = SqliteBudgetRepository(db);
        expect(await reopened.get(prior.id), isNull);
        expect((await reopened.get(original.id))!.data.amountCents, -10000);
        final saved = await reopened.readYear(2027);
        expect(saved.length, 12);
        expect(
          saved.singleWhere((b) => b.data.categoryId == child).data.amountCents,
          -37000,
        );
        expect(
          (await SqliteMovementRepository(db).readYear(2026))
              .single
              .data
              .amountCents,
          -35025,
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        await invalidation.close();
        await db.close();
        // Únicamente la carpeta temporal sintética creada por este recorrido.
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
