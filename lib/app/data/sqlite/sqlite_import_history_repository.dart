import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../features/budget/budget.dart';
import '../../../features/importing/importing.dart';
import '../../../features/movements/movements.dart';
import 'local_database.dart';

/// Usa las identidades inmutables de EP-004/012, sin guardar otro historial.
final class SqliteImportHistoryRepository implements ImportHistoryRepository {
  SqliteImportHistoryRepository(this.database);
  final LocalDatabase database;

  static const _batches = '''SELECT b.*, meta.format_version,
    COALESCE(meta.movement_count, (SELECT count(*) FROM import_rows
      WHERE batch_id=b.id AND record_kind='movement')) AS movement_count,
    COALESCE(meta.budget_count, (SELECT count(*) FROM import_rows
      WHERE batch_id=b.id AND record_kind='budget')) AS budget_count
    FROM import_batches b
    LEFT JOIN import_batch_metadata meta ON meta.batch_id=b.id''';

  static const _rows = '''SELECT r.*, o.payload,
    m.id AS movement_id, m.account_id, m.value_date,
    m.concept AS movement_concept, m.amount_cents AS movement_cents,
    m.category_id AS movement_category, m.discretion AS movement_discretion,
    b.id AS budget_id, b.month, b.category_id AS budget_category,
    b.concept AS budget_concept, b.amount_cents AS budget_cents,
    b.discretion AS budget_discretion
    FROM import_rows r
    LEFT JOIN import_row_originals o ON o.import_row_id=r.id
    LEFT JOIN movements m ON m.import_row_id=r.id
    LEFT JOIN budgets b ON b.import_row_id=r.id''';

  void _validateLimit(int limit) {
    if (limit < 1 || limit > 500) {
      throw ArgumentError.value(limit, 'limit', 'Debe estar entre 1 y 500.');
    }
  }

  @override
  Future<ImportHistoryPage<ImportBatch, ImportBatchCursor>> listBatches({
    int limit = 100,
    ImportBatchCursor? cursor,
  }) async {
    _validateLimit(limit);
    if (cursor != null && cursor.beforeBatchId.trim().isEmpty) {
      throw ArgumentError('Cursor de lotes inválido.');
    }
    final rows = await database
        .customSelect(
          '$_batches ${cursor == null ? '' : 'WHERE b.rowid<(SELECT rowid FROM import_batches WHERE id=?)'} '
          'ORDER BY b.rowid DESC LIMIT ?',
          variables: [
            if (cursor != null) Variable(cursor.beforeBatchId),
            Variable(limit + 1),
          ],
        )
        .get();
    final visible = rows.take(limit).toList();
    return ImportHistoryPage(
      visible.map(_batch).toList(),
      rows.length > limit
          ? ImportBatchCursor(visible.last.read<String>('id'))
          : null,
    );
  }

  @override
  Future<ImportBatch?> getBatch(String batchId) async {
    final rows = await database
        .customSelect('$_batches WHERE b.id=?', variables: [Variable(batchId)])
        .get();
    return rows.isEmpty ? null : _batch(rows.single);
  }

  ImportBatch _batch(QueryRow r) => ImportBatch(
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

  @override
  Future<ImportHistoryPage<ImportRowHistory, ImportRowCursor>> listRows(
    String batchId, {
    int limit = 100,
    ImportRowCursor? cursor,
  }) async {
    _validateLimit(limit);
    if (cursor != null &&
        (cursor.batchId != batchId || cursor.afterOrdinal < 2)) {
      throw ArgumentError('El cursor no corresponde al lote o es inválido.');
    }
    final rows = await database
        .customSelect(
          '$_rows WHERE r.batch_id=? '
          '${cursor == null ? '' : 'AND r.source_ordinal>?'} '
          'ORDER BY r.source_ordinal ASC LIMIT ?',
          variables: [
            Variable(batchId),
            if (cursor != null) Variable(cursor.afterOrdinal),
            Variable(limit + 1),
          ],
        )
        .get();
    final visible = rows.take(limit).toList();
    return ImportHistoryPage(
      visible.map(_row).toList(),
      rows.length > limit
          ? ImportRowCursor(batchId, visible.last.read<int>('source_ordinal'))
          : null,
    );
  }

  @override
  Future<ImportRowHistory?> getRow(String importRowId) async {
    final rows = await database
        .customSelect('$_rows WHERE r.id=?', variables: [Variable(importRowId)])
        .get();
    return rows.isEmpty ? null : _row(rows.single);
  }

  ImportRowHistory _row(QueryRow r) {
    final id = r.read<String>('id');
    final batchId = r.read<String>('batch_id');
    final ordinal = r.read<int>('source_ordinal');
    final kind = r.read<String>('record_kind') == 'movement'
        ? ImportRecordKind.movement
        : ImportRecordKind.budget;
    final payload = r.readNullable<String>('payload');
    final movementId = r.readNullable<String>('movement_id');
    final budgetId = r.readNullable<String>('budget_id');
    return ImportRowHistory(
      id: id,
      batchId: batchId,
      sourceOrdinal: ordinal,
      kind: kind,
      original: payload == null ? null : _original(payload, ordinal, kind),
      currentMovement: movementId == null
          ? null
          : MovementRecord(
              id: movementId,
              importRowId: id,
              batchId: batchId,
              sourceOrdinal: ordinal,
              data: MovementInput(
                accountId: r.read<String>('account_id'),
                valueDate: ValueDate.parse(r.read<String>('value_date')),
                concept: r.read<String>('movement_concept'),
                amountCents: r.read<int>('movement_cents'),
                categoryId: r.readNullable<String>('movement_category'),
                discretion: r.readNullable<String>('movement_discretion'),
              ),
            ),
      currentBudget: budgetId == null
          ? null
          : BudgetRecord(
              id: budgetId,
              importRowId: id,
              batchId: batchId,
              sourceOrdinal: ordinal,
              data: BudgetInput(
                month: BudgetMonth.parse(r.read<String>('month')),
                categoryId: r.read<String>('budget_category'),
                amountCents: r.read<int>('budget_cents'),
                concept: r.readNullable<String>('budget_concept'),
                discretion: r.readNullable<String>('budget_discretion'),
              ),
            ),
    );
  }
}

InterpretedImportRow _original(
  String payload,
  int ordinal,
  ImportRecordKind kind,
) {
  final data = jsonDecode(payload) as Map<String, dynamic>;
  if (data['version'] != 1) {
    throw const FormatException('Versión de originales no compatible.');
  }
  final fields = [
    for (final field in data['fields'] as List)
      ImportOriginalField(field['name'] as String, field['value'] as String),
  ];
  final originalCents = int.parse(data['originalCents'] as String);
  final convention = ImportAmountConvention.values.byName(
    data['amountConvention'] as String,
  );
  final amount = convention == ImportAmountConvention.economic
      ? ImportAmount.economic(originalCents)
      : ImportAmount.historicalBudget(originalCents);
  if (amount.internalCents != int.parse(data['internalCents'] as String)) {
    throw const FormatException('Importes originales incoherentes.');
  }
  final path = data['categoryPath'] as List?;
  final category = path == null
      ? null
      : ImportCategoryReference(path.cast<String>());
  if (kind == ImportRecordKind.movement) {
    final account = data['accountName'] as String?;
    return InterpretedMovement(
      sourceOrdinal: ordinal,
      originalFields: fields,
      concept: data['concept'] as String,
      amount: amount,
      discretion: data['discretion'] as String?,
      valueDate: ValueDate.parse(data['valueDate'] as String),
      account: account == null
          ? const ImportAccountReference.selectedAccount()
          : ImportAccountReference.named(account),
      category: category,
    );
  }
  return InterpretedBudget(
    sourceOrdinal: ordinal,
    originalFields: fields,
    concept: data['concept'] as String,
    amount: amount,
    discretion: data['discretion'] as String?,
    month: BudgetMonth.parse(data['month'] as String),
    category: category!,
  );
}
