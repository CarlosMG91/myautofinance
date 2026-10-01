import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../features/budget/budget.dart';
import 'local_database.dart';

final class SqliteBudgetRepository implements BudgetRepository {
  SqliteBudgetRepository(this.database);
  final LocalDatabase database;
  static const _select =
      'SELECT b.*,r.batch_id,r.source_ordinal FROM budgets b LEFT JOIN import_rows r ON r.id=b.import_row_id';

  @override
  Future<List<BudgetRecord>> readYear(
    int year, {
    bool incomeOnly = false,
  }) async {
    final from = BudgetMonth(year, 1);
    final args = <Variable>[Variable(from.value)];
    var where = 'b.month>=?';
    if (year < 9999) {
      where += ' AND b.month<?';
      args.add(Variable(BudgetMonth(year + 1, 1).value));
    }
    if (incomeOnly) {
      where += ''' AND b.category_id IN (WITH RECURSIVE income(id) AS (
SELECT id FROM categories WHERE parent_id IS NULL AND is_income=1
UNION ALL SELECT c.id FROM categories c JOIN income i ON c.parent_id=i.id
) SELECT id FROM income)''';
    }
    return (await database
            .customSelect(
              '$_select WHERE $where ORDER BY b.month,b.category_id,b.id',
              variables: args,
            )
            .get())
        .map(_read)
        .toList();
  }

  String _now() => DateTime.fromMillisecondsSinceEpoch(
    DateTime.now().millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();
  BudgetRecord _read(QueryRow r) => BudgetRecord(
    id: r.read<String>('id'),
    data: BudgetInput(
      month: BudgetMonth.parse(r.read<String>('month')),
      categoryId: r.read<String>('category_id'),
      amountCents: r.read<int>('amount_cents'),
      concept: r.readNullable<String>('concept'),
      discretion: r.readNullable<String>('discretion'),
    ),
    importRowId: r.readNullable<String>('import_row_id'),
    batchId: r.readNullable<String>('batch_id'),
    sourceOrdinal: r.readNullable<int>('source_ordinal'),
  );
  Future<void> _validate(
    BudgetInput data, {
    String? excludeId,
    String? previousCategory,
  }) async {
    if (data.concept != null && data.concept!.trim().isEmpty) {
      throw const BudgetFailure('Concepto vacío.');
    }
    final nodes = await database
        .customSelect(
          'SELECT archived FROM categories WHERE id=?',
          variables: [Variable(data.categoryId)],
        )
        .get();
    if (nodes.isEmpty ||
        (nodes.single.read<int>('archived') == 1 &&
            previousCategory != data.categoryId)) {
      throw const BudgetFailure('La categoría no existe o está archivada.');
    }
    final conflicts = await database
        .customSelect(
          '''
WITH RECURSIVE ancestors(id,parent_id) AS (
 SELECT id,parent_id FROM categories WHERE id=?
 UNION ALL SELECT c.id,c.parent_id FROM categories c JOIN ancestors a ON c.id=a.parent_id
), descendants(id) AS (
 SELECT ? UNION ALL SELECT c.id FROM categories c JOIN descendants d ON c.parent_id=d.id
) SELECT b.id FROM budgets b WHERE b.month=? AND b.id<>?
AND (b.category_id IN (SELECT id FROM ancestors) OR b.category_id IN (SELECT id FROM descendants))
''',
          variables: [
            Variable(data.categoryId),
            Variable(data.categoryId),
            Variable(data.month.value),
            Variable(excludeId ?? ''),
          ],
        )
        .get();
    if (conflicts.isNotEmpty) {
      throw const BudgetFailure(
        'Ya hay presupuesto en este nodo, un ancestro o un descendiente del mismo mes.',
      );
    }
  }

  Future<BudgetRecord> _insert(BudgetInput data, String? rowId) async {
    await _validate(data);
    final id = const Uuid().v4(), now = _now();
    await database.customStatement(
      'INSERT INTO budgets(id,month,category_id,amount_cents,concept,discretion,import_row_id,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)',
      [
        id,
        data.month.value,
        data.categoryId,
        data.amountCents,
        data.concept,
        data.discretion,
        rowId,
        now,
        now,
      ],
    );
    return (await get(id))!;
  }

  /// Solo el coordinador de lotes aporta la procedencia, en su transacción.
  Future<BudgetRecord> insertImported(BudgetInput data, String rowId) =>
      database.writeTransaction(() => _insert(data, rowId));
  @override
  Future<BudgetRecord> create(BudgetInput data) =>
      database.writeTransaction(() => _insert(data, null));
  @override
  Future<BudgetRecord?> get(String id) async {
    final rows = await database
        .customSelect('$_select WHERE b.id=?', variables: [Variable(id)])
        .get();
    return rows.isEmpty ? null : _read(rows.single);
  }

  @override
  Future<BudgetRecord> edit(String id, BudgetInput data) =>
      database.writeTransaction(() async {
        final old = await get(id);
        if (old == null) throw const BudgetFailure('La partida no existe.');
        await _validate(
          data,
          excludeId: id,
          previousCategory: old.data.categoryId,
        );
        await database.customStatement(
          'UPDATE budgets SET month=?,category_id=?,amount_cents=?,concept=?,discretion=?,updated_at=? WHERE id=?',
          [
            data.month.value,
            data.categoryId,
            data.amountCents,
            data.concept,
            data.discretion,
            _now(),
            id,
          ],
        );
        return (await get(id))!;
      });
  @override
  Future<void> delete(String id) => database.writeTransaction(() async {
    if (await get(id) == null) {
      throw const BudgetFailure('La partida no existe.');
    }
    await database.customStatement('DELETE FROM budgets WHERE id=?', [id]);
  });
  @override
  Future<List<BudgetRecord>> list(BudgetMonth month) async =>
      (await database
              .customSelect(
                '$_select WHERE b.month=? ORDER BY b.category_id,b.id',
                variables: [Variable(month.value)],
              )
              .get())
          .map(_read)
          .toList();
}
