import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../features/importing/importing.dart';
import '../../../features/movements/movements.dart';
import 'local_database.dart';
import 'sqlite_budget_repository.dart';
import 'sqlite_movement_repository.dart';

final class SqliteImportBatchRepository implements ImportBatchRepository {
  SqliteImportBatchRepository(this.database);
  final LocalDatabase database;
  @override
  Future<ImportBatch?> getByFingerprint(String sha256) async {
    final rows = await database
        .customSelect(
          'SELECT * FROM import_batches WHERE content_sha256=?',
          variables: [Variable(sha256)],
        )
        .get();
    if (rows.isEmpty) return null;
    final r = rows.single;
    return ImportBatch(
      id: r.read<String>('id'),
      sha256: r.read<String>('content_sha256'),
      source: r.read<String>('source_kind') == 'historical_csv'
          ? ImportSource.historicalCsv
          : ImportSource.bankXls,
      originalName: r.read<String>('original_name'),
      contractVersion: r.read<String>('contract_version'),
      importedAt: r.read<String>('imported_at'),
    );
  }

  @override
  Future<ImportBatch> create({
    required String sha256,
    required ImportSource source,
    required String originalName,
    required String contractVersion,
    List<ImportedMovement> movements = const [],
    List<ImportedBudget> budgets = const [],
  }) => database.transaction(() async {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256) ||
        originalName.trim().isEmpty ||
        originalName.contains('/') ||
        originalName.contains('\\') ||
        contractVersion.trim().isEmpty ||
        (movements.isEmpty && budgets.isEmpty)) {
      throw const MovementFailure(
        'Metadatos de importación inválidos o lote vacío.',
      );
    }
    if (await getByFingerprint(sha256) != null) {
      throw const MovementFailure('El archivo ya fue importado.');
    }
    final ordinals = <int>{};
    for (final row in movements) {
      if (row.sourceOrdinal < 2 || !ordinals.add(row.sourceOrdinal)) {
        throw const MovementFailure('Ordinal inválido o repetido.');
      }
    }
    for (final row in budgets) {
      if (source != ImportSource.historicalCsv ||
          row.sourceOrdinal < 2 ||
          !ordinals.add(row.sourceOrdinal)) {
        throw const MovementFailure(
          'Origen u ordinal presupuestario inválido o repetido.',
        );
      }
    }
    final id = const Uuid().v4();
    final now = movementTimestamp();
    await database.customStatement(
      'INSERT INTO import_batches(id,content_sha256,source_kind,original_name,contract_version,imported_at,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)',
      [
        id,
        sha256,
        source == ImportSource.historicalCsv ? 'historical_csv' : 'bank_xls',
        originalName,
        contractVersion,
        now,
        now,
        now,
      ],
    );
    final repo = SqliteMovementRepository(database);
    for (final row in movements) {
      final rowId = const Uuid().v4();
      await database.customStatement(
        "INSERT INTO import_rows(id,batch_id,source_ordinal,record_kind,created_at,updated_at) VALUES(?,?,?,'movement',?,?)",
        [rowId, id, row.sourceOrdinal, now, now],
      );
      await repo.insertImported(row.data, rowId);
    }
    final budgetRepo = SqliteBudgetRepository(database);
    for (final row in budgets) {
      final rowId = const Uuid().v4();
      await database.customStatement(
        "INSERT INTO import_rows(id,batch_id,source_ordinal,record_kind,created_at,updated_at) VALUES(?,?,?,'budget',?,?)",
        [rowId, id, row.sourceOrdinal, now, now],
      );
      await budgetRepo.insertImported(row.data, rowId);
    }
    return (await getByFingerprint(sha256))!;
  });
}
