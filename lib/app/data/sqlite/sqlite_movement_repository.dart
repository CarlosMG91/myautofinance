import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../features/movements/movements.dart';
import 'local_database.dart';

String movementTimestamp() => DateTime.fromMillisecondsSinceEpoch(
  DateTime.now().millisecondsSinceEpoch,
  isUtc: true,
).toIso8601String();

final class SqliteMovementRepository implements MovementRepository {
  SqliteMovementRepository(this.database);
  final LocalDatabase database;
  static const _select =
      'SELECT m.*,r.batch_id,r.source_ordinal FROM movements m LEFT JOIN import_rows r ON r.id=m.import_row_id';

  MovementRecord _read(QueryRow r) => MovementRecord(
    id: r.read<String>('id'),
    data: MovementInput(
      accountId: r.read<String>('account_id'),
      valueDate: ValueDate.parse(r.read<String>('value_date')),
      concept: r.read<String>('concept'),
      amountCents: r.read<int>('amount_cents'),
      categoryId: r.readNullable<String>('category_id'),
      discretion: r.readNullable<String>('discretion'),
    ),
    importRowId: r.readNullable<String>('import_row_id'),
    batchId: r.readNullable<String>('batch_id'),
    sourceOrdinal: r.readNullable<int>('source_ordinal'),
  );

  Future<void> _validate(MovementInput data, {String? previousCategory}) async {
    if (data.amountCents == 0 || data.concept.trim().isEmpty) {
      throw const MovementFailure('Importe cero o concepto vacío.');
    }
    final accounts = await database
        .customSelect(
          'SELECT * FROM accounts WHERE id=?',
          variables: [Variable(data.accountId)],
        )
        .get();
    final month = '${data.valueDate.value.substring(0, 7)}-01';
    if (accounts.isEmpty ||
        accounts.single.read<String>('kind') != 'account' ||
        month.compareTo(accounts.single.read<String>('active_from')) < 0 ||
        (accounts.single.readNullable<String>('active_through') != null &&
            month.compareTo(accounts.single.read<String>('active_through')) >
                0)) {
      throw const MovementFailure('La cuenta no existe o no está vigente.');
    }
    if (data.categoryId != null) {
      final categories = await database
          .customSelect(
            'SELECT archived FROM categories WHERE id=?',
            variables: [Variable(data.categoryId!)],
          )
          .get();
      if (categories.isEmpty ||
          (categories.single.read<int>('archived') == 1 &&
              data.categoryId != previousCategory)) {
        throw const MovementFailure('La categoría no existe o está archivada.');
      }
    }
  }

  /// El coordinador llama dentro de la misma transacción del lote.
  Future<MovementRecord> insertImported(
    MovementInput data,
    String importRowId,
  ) => database.writeTransaction(() => _insert(data, importRowId));
  Future<MovementRecord> _insert(MovementInput data, String? rowId) async {
    await _validate(data);
    final id = const Uuid().v4();
    final now = movementTimestamp();
    await database.customStatement(
      'INSERT INTO movements(id,account_id,value_date,concept,amount_cents,category_id,discretion,import_row_id,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?)',
      [
        id,
        data.accountId,
        data.valueDate.value,
        data.concept,
        data.amountCents,
        data.categoryId,
        data.discretion,
        rowId,
        now,
        now,
      ],
    );
    return (await get(id))!;
  }

  @override
  Future<MovementRecord> create(MovementInput data) =>
      database.writeTransaction(() => _insert(data, null));
  @override
  Future<MovementRecord?> get(String id) async {
    final rows = await database
        .customSelect('$_select WHERE m.id=?', variables: [Variable(id)])
        .get();
    return rows.isEmpty ? null : _read(rows.single);
  }

  Future<MovementRecord> _require(String id) async =>
      await get(id) ??
      (throw const MovementFailure('El movimiento no existe.'));
  @override
  Future<MovementRecord> edit(String id, MovementInput data) =>
      database.writeTransaction(() async {
        final old = await _require(id);
        await _validate(data, previousCategory: old.data.categoryId);
        await database.customStatement(
          'UPDATE movements SET account_id=?,value_date=?,concept=?,amount_cents=?,category_id=?,updated_at=? WHERE id=?',
          [
            data.accountId,
            data.valueDate.value,
            data.concept,
            data.amountCents,
            data.categoryId,
            movementTimestamp(),
            id,
          ],
        );
        return (await get(id))!;
      });
  @override
  Future<void> setDiscretion(String id, String? discretion) =>
      database.writeTransaction(() async {
        await _require(id);
        await database.customStatement(
          'UPDATE movements SET discretion=?,updated_at=? WHERE id=?',
          [discretion, movementTimestamp(), id],
        );
      });
  @override
  Future<void> delete(String id) => database.writeTransaction(() async {
    await _require(id);
    await database.customStatement('DELETE FROM movements WHERE id=?', [id]);
  });
  @override
  Future<List<MovementRecord>> list({
    required ValueDate from,
    required ValueDate? until,
    String? accountId,
    String? categoryId,
    bool unclassifiedOnly = false,
    MovementCursor? after,
    int limit = 100,
  }) async {
    if (limit < 1 ||
        limit > 500 ||
        (until != null && until.compareTo(from) <= 0) ||
        (until == null && !from.value.startsWith('9999-')) ||
        (unclassifiedOnly && categoryId != null)) {
      throw const MovementFailure('Rango o paginación inválidos.');
    }
    final clauses = ['m.value_date>=?'];
    final args = <Variable>[Variable(from.value)];
    if (until != null) {
      clauses.add('m.value_date<?');
      args.add(Variable(until.value));
    }
    if (accountId != null) {
      clauses.add('m.account_id=?');
      args.add(Variable(accountId));
    }
    if (categoryId != null) {
      clauses.add('m.category_id=?');
      args.add(Variable(categoryId));
    }
    if (unclassifiedOnly) clauses.add('m.category_id IS NULL');
    if (after != null) {
      clauses.add('(m.value_date,m.id)>(?,?)');
      args.addAll([Variable(after.valueDate.value), Variable(after.id)]);
    }
    args.add(Variable(limit));
    return (await database
            .customSelect(
              '$_select WHERE ${clauses.join(' AND ')} ORDER BY m.value_date,m.id LIMIT ?',
              variables: args,
            )
            .get())
        .map(_read)
        .toList();
  }
}
