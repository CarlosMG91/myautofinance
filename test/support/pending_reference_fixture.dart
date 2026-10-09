import 'dart:convert';

import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_wealth_repository.dart';
import 'package:myautofinance/app/import_factory.dart';
import 'package:myautofinance/features/importing/data/sha256_import_fingerprint.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

import 'synthetic_import_adapter.dart';

/// MA-TSK-138: ejecuta el dataset de MA-TSK-137 con UUID reales, sin lectores
/// CSV/XLS. Las altas importadas pasan por preview/confirmación EP-012.
class PendingReferenceFixture {
  final ids = <String, String>{};
  final files = <String, ImportFile>{};

  Future<void> seed(LocalDatabase db) async {
    final accounts = SqliteAccountRepository(db);
    for (final key in ['a1', 'a2']) {
      ids[key] = (await accounts.create(
        name: 'Cuenta diaria',
        kind: AccountKind.account,
        activeFrom: Month(2025, 1),
        liquidity: Liquidity.liquid,
      )).id;
    }
    final categories = SqliteCategoryRepository(db);
    ids['c-hogar'] = (await categories.create(name: 'Hogar')).id;
    ids['c-alimentacion'] = (await categories.create(
      name: 'Alimentación',
      parentId: ids['c-hogar'],
    )).id;
    ids['c-transporte'] = (await categories.create(name: 'Transporte')).id;
    ids['c-archivo'] = (await categories.create(name: 'Archivo')).id;
    await categories.setArchived(ids['c-archivo']!, archived: true);

    Map<String, Object?> real(
      int ordinal,
      String account,
      String date,
      String concept,
      int cents, {
      List<String>? category,
    }) => {
      'kind': 'REAL',
      'ordinal': ordinal + 1, // EP-012 reserva el ordinal 1 a la cabecera.
      'account': account,
      'date': date,
      'concept': concept,
      'cents': cents,
      'category': category,
      'discretion': 'Sintético',
      'fields': [
        {'name': 'concepto', 'value': concept},
        {'name': 'importe', 'value': cents.toString()},
        {'name': 'importe', 'value': 'original repetido sin normalizar'},
      ],
    };
    final documents = {
      'l1': [
        real(1, 'a1', '2026-06-30', 'Café Plaza', -450),
        real(2, 'a1', '2026-06-29', 'Café Plaza', -450),
        real(3, 'a2', '2026-06-29', 'Café Plaza', -450),
        {
          'kind': 'PRESUPUESTO',
          'ordinal': 5,
          'month': '2026-06',
          'concept': 'Mercado',
          'cents': 2300,
          'category': ['Hogar'],
        },
      ],
      'l2': [
        real(1, 'a2', '2026-05-15', 'Abono nómina', 120000),
        real(2, 'a1', '2025-12-01', 'Mercado', -2300),
        real(
          3,
          'a1',
          '2025-11-30',
          'Café Plaza',
          -450,
          category: ['Hogar', 'Alimentación'],
        ),
      ],
    };
    final services = createImportServices(db);
    for (final entry in documents.entries) {
      final file = ImportFile.fromBytes(
        bytes: utf8.encode(jsonEncode({'rows': entry.value})),
        fingerprint: const Sha256ImportFingerprint(),
        source: ImportSource.historicalCsv,
        originalName: 'pendientes-${entry.key}-sintetico.json',
      );
      files[entry.key] = file;
      final session = ImportSession(
        file: file,
        interpretation: await const SyntheticImportAdapter(
          ImportSource.historicalCsv,
        ).interpret(file),
      );
      final review = await services.previewer.preview(
        session,
        bindings: ImportReferenceBindings(
          accounts: {
            for (final key in ['a1', 'a2'])
              ImportAccountReference.named(key): ids[key]!,
          },
          categories: {
            ImportCategoryReference(['Hogar']): ids['c-hogar']!,
            ImportCategoryReference(['Hogar', 'Alimentación']):
                ids['c-alimentacion']!,
          },
        ),
      );
      if (!review.canRequestConfirmation) {
        throw StateError(
          'Fixture pendiente inválido: ${review.issues.map((i) => i.reason).join('; ')}',
        );
      }
      final result = await services.confirmer.confirm(
        ImportConfirmationRequest(
          review: review,
          reviewedOverlapKeys: review.overlaps.map((o) => o.key).toSet(),
        ),
      );
      if (result is! ImportConfirmed) throw StateError('Fixture no confirmado');
      ids[entry.key] = result.batch.id;
      final rows = await services.history.listRows(result.batch.id);
      for (final row in rows.items) {
        final key = row.kind == ImportRecordKind.budget
            ? 'b01'
            : 'r0${row.sourceOrdinal - 1 + (entry.key == 'l1' ? 0 : 3)}';
        ids[key] = row.currentMovement?.id ?? row.currentBudget!.id;
      }
    }
    ids['r07'] = (await SqliteMovementRepository(db).create(
      MovementInput(
        accountId: ids['a1']!,
        valueDate: ValueDate(2026, 6, 30),
        concept: 'Café Plaza',
        amountCents: -450,
        discretion: 'Sintético',
      ),
    )).id;
    final wealth = SqliteWealthRepository(db);
    await wealth.setValue(Month(2026, 6), ids['a1']!, 100000);
    await wealth.setValue(Month(2026, 6), ids['a2']!, 200000);
  }

  String key(String id) => ids.entries.singleWhere((e) => e.value == id).key;

  Future<Map<String, Object?>> image(LocalDatabase db) async {
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        .get();
    return {
      for (final table in tables)
        table.read<String>(
          'name',
        ): (await db
                .customSelect(
                  'SELECT * FROM "${table.read<String>('name')}" ORDER BY rowid',
                )
                .get())
            .map((r) => Map<String, Object?>.of(r.data))
            .toList(),
    };
  }

  /// Todo lo persistido salvo los únicos campos que cambia categorizar.
  Map<String, Object?> preserved(
    Map<String, Object?> image, {
    required Iterable<String> allowed,
  }) => {
    for (final entry in image.entries)
      if (entry.key != 'database_state')
        entry.key: entry.key != 'movements'
            ? entry.value
            : (entry.value as List)
                  .map(
                    (row) => allowed.contains((row as Map)['id'])
                        ? (Map<String, Object?>.from(row)
                            ..remove('category_id')
                            ..remove('updated_at'))
                        : Map<String, Object?>.from(row),
                  )
                  .toList(),
  };
}
