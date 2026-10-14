import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/annual_actual_query_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/features/actual_spending/actual_spending.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  final manifest = jsonDecode(
    File('docs/ep-022/fixtures/referencias.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final cases = manifest['cases'] as Map<String, dynamic>;
  for (final name in ['F', 'J', 'K', 'L']) {
    test(
      'MA-TSK-179/$name: SQLite contrasta fixture, ramas y origen UUID',
      () async {
        final db = LocalDatabase(
          NativeDatabase.memory(setup: configureConnection),
        );
        final invalidation = CategoryReadInvalidation();
        addTearDown(() async {
          await invalidation.close();
          await db.close();
        });
        final fixture = cases[name] as Map<String, dynamic>;
        final categories = SqliteCategoryRepository(db);
        final aliases = <String, String>{};
        Future<void> category(
          String id,
          String? parent, {
          bool income = false,
        }) async {
          aliases[id] = (await categories.create(
            name: id,
            parentId: aliases[parent],
            isIncome: parent == null ? income : null,
          )).id;
        }

        if (name == 'L') {
          for (final item in fixture['categories'] as List<dynamic>) {
            await category(
              item['id'] as String,
              item['parent'] as String?,
              income: item['isIncome'] as bool,
            );
          }
          for (var m = 1; m <= 12; m++) {
            for (final entry
                in (fixture['monthlyBudgetsCents']['everyMonth']
                        as Map<String, dynamic>)
                    .entries) {
              await SqliteBudgetRepository(db).create(
                BudgetInput(
                  month: BudgetMonth(2026, m),
                  categoryId: aliases[entry.key]!,
                  amountCents: entry.value as int,
                ),
              );
            }
          }
        } else {
          for (final root in [
            'ingresos',
            'vivienda',
            'alimentacion',
            'ahorro',
            'ocio',
          ]) {
            await category(root, null, income: root == 'ingresos');
          }
          for (final entry in {
            'ing-salario': 'ingresos',
            'viv-alquiler': 'vivienda',
            'supermercado': 'alimentacion',
            'ali-compra': 'supermercado',
            'aho-cuenta': 'ahorro',
          }.entries) {
            await category(entry.key, entry.value);
          }
          aliases['ocio-raiz'] = aliases['ocio']!;
        }
        final accounts = SqliteAccountRepository(db);
        Future<String> account(String label) async => (await accounts.create(
          name: label,
          kind: AccountKind.account,
          activeFrom: Month(2026, 1),
          liquidity: Liquidity.liquid,
        )).id;
        final principal = await account('Principal sintética');
        final savings = await account('Ahorro sintético');
        final rows = <dynamic>[
          if (fixture['base'] == 'F')
            ...(cases['F']['movements'] as List<dynamic>),
          ...((fixture['movements'] ?? fixture['addedMovements'])
              as List<dynamic>),
        ];
        final movements = SqliteMovementRepository(db);
        final ids = <String, String>{};
        for (final row in rows) {
          final record = await movements.create(
            MovementInput(
              accountId: row.length > 4 ? savings : principal,
              valueDate: ValueDate.parse(row[1] as String),
              concept: row[0] as String,
              categoryId: aliases[row[2]],
              amountCents: row[3] as int,
            ),
          );
          ids[row[0] as String] = record.id;
        }
        final data = await createAnnualActualQuery(
          database: db,
          invalidation: invalidation,
        ).read(2026);
        expect(
          data.months.map((m) => m.amountCents),
          fixture['monthlyTotalCents'],
        );
        expect(data.annualTotal.amountCents, fixture['annualTotalCents']);
        expect(data.annualTotal.movementCount, rows.length);
        for (final entry
            in (fixture['rootAnnualCents'] as Map<String, dynamic>).entries) {
          final total = entry.key == 'unclassified'
              ? data.unclassified.annualTotal
              : data.rows
                    .singleWhere((r) => r.categoryId == aliases[entry.key])
                    .annualTotal;
          expect(total.amountCents, entry.value, reason: '$name/${entry.key}');
        }
        for (final categoryId in {...aliases.values, null}) {
          final visible = categoryId == null
              ? data.unclassified
              : data.rows.where((r) => r.categoryId == categoryId).firstOrNull;
          if (visible == null) continue;
          final filter = AnnualActualDetail(
            year: 2026,
            categoryId: categoryId,
            unclassified: categoryId == null,
          ).movements;
          final page = await movements.readPage(
            from: filter.from,
            until: filter.until,
            categoryId: filter.categoryId,
            categoryScope: filter.scope,
            unclassifiedOnly: filter.unclassified,
          );
          expect(page.subtotalCents, visible.annualTotal.amountCents);
          expect(page.records.length, visible.annualTotal.movementCount);
          // Oráculo por registros/árbol, independiente de los agregados SQL.
          final branch = <String>{};
          if (categoryId != null) {
            branch.add(categoryId);
            final nodes = await categories.list();
            var previous = -1;
            while (previous != branch.length) {
              previous = branch.length;
              branch.addAll(
                nodes
                    .where((n) => branch.contains(n.parentId))
                    .map((n) => n.id),
              );
            }
          }
          final expected = rows
              .where(
                (r) => categoryId == null
                    ? r[2] == null
                    : branch.contains(aliases[r[2]]),
              )
              .map((r) => ids[r[0]])
              .toSet();
          expect(page.records.map((r) => r.id).toSet(), expected);
        }
        if (name == 'L') {
          expect(
            await SqliteBudgetRepository(db).readYear(2026),
            hasLength(24),
          );
          expect(data.annualTotal.amountCents, 240000);
        }
      },
    );
  }
}
