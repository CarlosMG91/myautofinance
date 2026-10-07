import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../features/importing/importing.dart';
import '../../../features/importing/data/sha256_import_fingerprint.dart';
import '../../../features/movements/movements.dart';
import '../../../features/wealth/wealth.dart';
import 'local_database.dart';
import 'sqlite_account_repository.dart';
import 'sqlite_budget_repository.dart';
import 'sqlite_category_repository.dart';
import 'sqlite_import_preview_source.dart';
import 'sqlite_movement_repository.dart';

final class SqliteImportBatchRepository implements ImportBatchRepository {
  SqliteImportBatchRepository(this.database);
  final LocalDatabase database;
  @override
  Future<ImportBatch?> getByFingerprint(String sha256) async {
    final rows = await database
        .customSelect(
          '''SELECT b.*, meta.format_version,
          (SELECT count(*) FROM import_rows WHERE batch_id=b.id AND record_kind='movement') AS movement_count,
          (SELECT count(*) FROM import_rows WHERE batch_id=b.id AND record_kind='budget') AS budget_count
          FROM import_batches b LEFT JOIN import_batch_metadata meta ON meta.batch_id=b.id
          WHERE content_sha256=?''',
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
      formatVersion: r.readNullable<String>('format_version'),
      movementCount: r.read<int>('movement_count'),
      budgetCount: r.read<int>('budget_count'),
    );
  }

  @override
  Future<ImportConfirmationResult> confirm(
    ImportConfirmationRequest request,
  ) async {
    final session = request.review.session;
    try {
      return await database.writeTransaction(() async {
        if (!session.file.matchesFingerprint(const Sha256ImportFingerprint())) {
          throw _ConfirmationRejected([
            const ImportIssue(
              code: ImportIssueCode.invalidFile,
              field: 'sha256',
              reason:
                  'La huella no corresponde a los bytes completos del archivo.',
            ),
          ]);
        }
        // Reserva la escritura ANTES de leer: ningún otro escritor puede
        // invalidar catálogos/solapamientos entre la revalidación y las altas.
        // Este no-op no activa el seguimiento de mutaciones financieras.
        await database.customStatement(
          'UPDATE database_state SET revision=revision WHERE singleton=1',
        );
        final previous = await getByFingerprint(session.file.sha256);
        if (previous != null) throw _AlreadyImported(previous);

        final current = await ValidatingImportPreviewer(
          SqliteImportPreviewSource(database),
        ).preview(session, bindings: request.review.bindings);
        final issues = <ImportIssue>[...current.issues];
        for (final pending in current.pendingReferences) {
          for (final ordinal in pending.sourceOrdinals) {
            issues.add(
              ImportIssue(
                code: ImportIssueCode.unresolvedReference,
                sourceOrdinal: ordinal,
                reason: pending.reason,
              ),
            );
          }
        }
        for (final overlap in current.overlaps) {
          if (!request.reviewedOverlapKeys.contains(overlap.key) ||
              !request.review.overlaps.any((o) => o.key == overlap.key)) {
            issues.add(
              ImportIssue(
                code: ImportIssueCode.staleReview,
                sourceOrdinal: overlap.sourceOrdinal,
                reason:
                    'Hay un solapamiento nuevo con ${overlap.existingMovementId}. Actualiza la revisión y revísalo expresamente.',
              ),
            );
          }
        }
        if (issues.isNotEmpty) throw _ConfirmationRejected(issues);
        if (!current.canRequestConfirmation) {
          throw _ConfirmationRejected([
            const ImportIssue(
              code: ImportIssueCode.staleReview,
              reason:
                  'Las referencias ya no son válidas. Actualiza la revisión.',
            ),
          ]);
        }

        final bindings = current.bindings;
        final accounts = {...bindings.accounts};
        for (final entry in bindings.newAccounts.entries) {
          final plan = entry.value;
          final account = await SqliteAccountRepository(database).create(
            name: plan.name,
            kind: AccountKind.account,
            activeFrom: plan.activeFrom,
            activeThrough: plan.activeThrough,
            liquidity: plan.liquidity,
          );
          accounts[entry.key] = account.id;
        }
        final categories = {...bindings.categories};
        Future<String> createCategory(ImportCategoryReference ref) async {
          final existing = categories[ref];
          if (existing != null) return existing;
          final plan = bindings.newCategories[ref]!;
          final target = plan.parent;
          final parentId = target == null
              ? null
              : target.existingId ??
                    await createCategory(target.proposedReference!);
          final node = await SqliteCategoryRepository(database).create(
            name: plan.name,
            parentId: parentId,
            isIncome: plan.isIncome,
          );
          categories[ref] = node.id;
          return node.id;
        }

        for (final ref in bindings.newCategories.keys) {
          await createCategory(ref);
        }
        final movements = <ImportedMovement>[];
        final budgets = <ImportedBudget>[];
        for (final row in session.interpretation.rows) {
          switch (row) {
            case InterpretedMovement():
              movements.add(
                ImportedMovement(
                  row.sourceOrdinal,
                  row.toMovementInput(
                    accountId: accounts[row.account]!,
                    categoryId: row.category == null
                        ? null
                        : categories[row.category]!,
                  ),
                ),
              );
            case InterpretedBudget():
              budgets.add(
                ImportedBudget(
                  row.sourceOrdinal,
                  row.toBudgetInput(categoryId: categories[row.category]!),
                ),
              );
          }
        }
        final batch = await create(
          sha256: session.file.sha256,
          source: session.file.source,
          originalName: session.file.originalName,
          contractVersion: session.interpretation.contractVersion,
          movements: movements,
          budgets: budgets,
        );
        final insertedRows = await database
            .customSelect(
              'SELECT id,source_ordinal FROM import_rows WHERE batch_id=?',
              variables: [Variable(batch.id)],
            )
            .get();
        final rowIds = {
          for (final row in insertedRows)
            row.read<int>('source_ordinal'): row.read<String>('id'),
        };
        for (final row in session.interpretation.rows) {
          await _insertChecked(
            'INSERT INTO import_row_originals(import_row_id,payload) VALUES(?,?)',
            [rowIds[row.sourceOrdinal]!, _originalPayload(row)],
          );
        }
        await _insertChecked(
          'INSERT INTO import_batch_metadata(batch_id,format_version,movement_count,budget_count) VALUES(?,?,?,?)',
          [
            batch.id,
            session.interpretation.formatVersion,
            movements.length,
            budgets.length,
          ],
        );
        return ImportConfirmed(
          batch: (await getByFingerprint(session.file.sha256))!,
          movementCount: movements.length,
          budgetCount: budgets.length,
        );
      });
    } on _AlreadyImported catch (previous) {
      // También revierte la reserva y el estado TEMP de seguimiento: cero altas.
      return ImportAlreadyImported(previous.batch);
    } on _ConfirmationRejected catch (failure) {
      return ImportRejected(failure.issues);
    } catch (_) {
      // La transacción (incluido su incremento de revisión) ya ha revertido.
      return ImportRejected([
        const ImportIssue(
          code: ImportIssueCode.persistence,
          reason: 'No se pudo confirmar la carga completa. No se guardó ningún alta; actualiza la revisión y vuelve a intentarlo.',
        ),
      ]);
    }
  }

  Future<void> _insertChecked(String sql, List<Object?> arguments) async {
    await database.customStatement(sql, arguments);
    if ((await database.customSelect('SELECT changes() AS n').getSingle())
            .read<int>('n') !=
        1) {
      throw StateError('No se guardó la procedencia completa.');
    }
  }

  @override
  Future<ImportBatch> create({
    required String sha256,
    required ImportSource source,
    required String originalName,
    required String contractVersion,
    List<ImportedMovement> movements = const [],
    List<ImportedBudget> budgets = const [],
  }) => database.writeTransaction(() async {
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

final class _ConfirmationRejected implements Exception {
  const _ConfirmationRejected(this.issues);
  final List<ImportIssue> issues;
}

final class _AlreadyImported implements Exception {
  const _AlreadyImported(this.batch);
  final ImportBatch batch;
}

/// JSON versionado, campos como lista para preservar orden/nombres repetidos.
/// Los importes son strings decimales para conservar int64 en consumidores JSON.
String _originalPayload(InterpretedImportRow row) => jsonEncode({
  'version': 1,
  'fields': [
    for (final field in row.originalFields)
      {'name': field.name, 'value': field.value},
  ],
  'concept': row.concept,
  'discretion': row.discretion,
  'originalCents': row.amount.originalCents.toString(),
  'internalCents': row.amount.internalCents.toString(),
  'amountConvention': row.amount.convention.name,
  'categoryPath': switch (row) {
    InterpretedMovement() => row.category?.path,
    InterpretedBudget() => row.category.path,
  },
  if (row is InterpretedMovement) ...{
    'valueDate': row.valueDate.value,
    'accountName': row.account.name,
  },
  if (row is InterpretedBudget) 'month': row.month.value,
});
