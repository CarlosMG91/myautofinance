import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../features/movements/movements.dart';
import 'local_database.dart';
import 'concept_search_key.dart';

String movementTimestamp() => DateTime.fromMillisecondsSinceEpoch(
  DateTime.now().millisecondsSinceEpoch,
  isUtc: true,
).toIso8601String();

final class SqliteMovementRepository
    implements MovementRepository, PendingMovementRepository {
  SqliteMovementRepository(this.database);
  final LocalDatabase database;
  static const _select =
      'SELECT m.*,r.batch_id,r.source_ordinal FROM movements m LEFT JOIN import_rows r ON r.id=m.import_row_id';

  @override
  Future<List<MovementRecord>> readMonth(
    int year,
    int month, {
    String? categoryId,
  }) {
    final from = ValueDate(year, month, 1);
    final until = year == 9999 && month == 12
        ? null
        : ValueDate(
            month == 12 ? year + 1 : year,
            month == 12 ? 1 : month + 1,
            1,
          );
    return _readPeriod(from, until, categoryId);
  }

  @override
  Future<List<MovementRecord>> readYear(int year, {String? categoryId}) =>
      _readPeriod(
        ValueDate(year, 1, 1),
        year == 9999 ? null : ValueDate(year + 1, 1, 1),
        categoryId,
      );

  Future<List<MovementRecord>> _readPeriod(
    ValueDate from,
    ValueDate? until,
    String? categoryId,
  ) async {
    final filter = _filter(
      from: from,
      until: until,
      categoryId: categoryId,
      categoryScope: MovementCategoryScope.branch,
    );
    return (await database
            .customSelect(
              '$_select WHERE ${filter.where} ORDER BY m.value_date,m.id',
              variables: filter.arguments,
            )
            .get())
        .map(_read)
        .toList();
  }

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
        normalizeMovementDiscretion(data.discretion),
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
          [normalizeMovementDiscretion(discretion), movementTimestamp(), id],
        );
      });
  @override
  Future<void> delete(String id) => database.writeTransaction(() async {
    await _require(id);
    await database.customStatement('DELETE FROM movements WHERE id=?', [id]);
  });

  @override
  Future<void> setCategoryBatch(List<String> ids, String? categoryId) {
    final selection = MovementSelection(ids);
    return database.writeTransaction(() async {
      final records = await _requireSelection(selection);
      if (categoryId != null) {
        final category = await database
            .customSelect(
              'SELECT archived FROM categories WHERE id=?',
              variables: [Variable(categoryId)],
            )
            .getSingleOrNull();
        if (category == null || category.read<int>('archived') != 0) {
          throw const MovementFailure(
            'La categoría no existe o está archivada.',
          );
        }
      }
      final now = movementTimestamp();
      for (final record in records) {
        if (record.data.categoryId == categoryId) continue;
        final changed = await database.customUpdate(
          'UPDATE movements SET category_id=?,updated_at=? WHERE id=?',
          variables: [
            Variable<String>(categoryId),
            Variable(now),
            Variable(record.id),
          ],
        );
        if (changed != 1) {
          throw const MovementFailure('No se pudo categorizar todo el lote.');
        }
      }
    });
  }

  @override
  Future<void> deleteBatch(List<String> ids) {
    final selection = MovementSelection(ids);
    return database.writeTransaction(() async {
      await _requireSelection(selection);
      for (final id in selection.ids) {
        final deleted = await database.customUpdate(
          'DELETE FROM movements WHERE id=?',
          variables: [Variable(id)],
        );
        if (deleted != 1) {
          throw const MovementFailure('No se pudo borrar todo el lote.');
        }
      }
    });
  }

  @override
  Future<void> assignPendingCategory(
    PendingMovementSelection selection,
    String categoryId,
  ) {
    MovementSelection([categoryId]);
    return database.writeTransaction(() async {
      if (!identical(selection.databaseIdentity, database) ||
          selection.datasetId != (await database.readState()).datasetId) {
        throw const MovementFailure(
          'La base local ha cambiado. Selecciona de nuevo los pendientes.',
        );
      }
      final records = await _requireSelection(selection.movements);
      if (records.any(
        (record) =>
            record.importRowId == null || record.data.categoryId != null,
      )) {
        throw const MovementFailure(
          'Algún movimiento ya no es un importado pendiente. Revisa la selección.',
        );
      }
      final category = await database
          .customSelect(
            'SELECT archived FROM categories WHERE id=?',
            variables: [Variable(categoryId)],
          )
          .getSingleOrNull();
      if (category == null || category.read<int>('archived') != 0) {
        throw const MovementFailure('La categoría no existe o está archivada.');
      }
      final now = movementTimestamp();
      for (final record in records) {
        // El predicado protege también frente a un cambio durante la escritura.
        final changed = await database.customUpdate(
          'UPDATE movements SET category_id=?,updated_at=? '
          'WHERE id=? AND import_row_id IS NOT NULL AND category_id IS NULL',
          variables: [Variable(categoryId), Variable(now), Variable(record.id)],
        );
        if (changed != 1) {
          throw const MovementFailure(
            'No se pudo categorizar todo el lote pendiente.',
          );
        }
      }
    });
  }

  @override
  Future<PendingMovementPage> readPendingPage({
    PendingMovementQuery? query,
    MovementCursor? after,
    int limit = 100,
  }) async {
    _validateLimit(limit);
    final filters = query ?? PendingMovementQuery();
    final filter = _filter(
      from: filters.from,
      until: filters.until,
      accountId: filters.accountId,
      concept: filters.concept,
      unclassifiedOnly: true,
      importedOnly: true,
      batchId: filters.batchId,
      openPeriod: true,
    );
    return database.transaction(() async {
      final state = await database.readState();
      final count =
          (await database
                  .customSelect(
                    'SELECT count(*) AS total FROM movements m WHERE ${filter.where}',
                    variables: filter.arguments,
                  )
                  .getSingle())
              .read<int>('total');
      final rows = await _pageRecords(filter, after, limit + 1);
      final hasMore = rows.length > limit;
      final visible = hasMore ? rows.sublist(0, limit) : rows;
      return PendingMovementPage(
        records: visible,
        totalCount: count,
        nextCursor: hasMore
            ? MovementCursor(visible.last.data.valueDate, visible.last.id)
            : null,
        databaseIdentity: database,
        datasetId: state.datasetId,
      );
    });
  }

  Future<List<MovementRecord>> _requireSelection(
    MovementSelection selection,
  ) async {
    final records = <MovementRecord>[];
    // Sin IN ni límite de página: el tamaño del lote no depende del límite de
    // parámetros SQLite. Cada UUID debe seguir existiendo antes de escribir.
    for (final id in selection.ids) {
      records.add(await _require(id));
    }
    return records;
  }

  @override
  Future<List<MovementRecord>> list({
    required ValueDate from,
    required ValueDate? until,
    String? accountId,
    String? categoryId,
    MovementCategoryScope categoryScope = MovementCategoryScope.direct,
    bool unclassifiedOnly = false,
    String? concept,
    MovementCursor? after,
    int limit = 100,
  }) async {
    _validateLimit(limit);
    final filter = _filter(
      from: from,
      until: until,
      accountId: accountId,
      categoryId: categoryId,
      categoryScope: categoryScope,
      unclassifiedOnly: unclassifiedOnly,
      concept: concept,
    );
    return _pageRecords(filter, after, limit);
  }

  @override
  Future<MovementPage> readPage({
    required ValueDate from,
    required ValueDate? until,
    String? accountId,
    String? categoryId,
    MovementCategoryScope categoryScope = MovementCategoryScope.direct,
    bool unclassifiedOnly = false,
    String? concept,
    MovementCursor? after,
    int limit = 100,
  }) async {
    _validateLimit(limit);
    final filter = _filter(
      from: from,
      until: until,
      accountId: accountId,
      categoryId: categoryId,
      categoryScope: categoryScope,
      unclassifiedOnly: unclassifiedOnly,
      concept: concept,
    );
    return database.transaction(() async {
      // Acumulación exacta: no pierde céntimos ni falla por overflow intermedio
      // cuando importes de signo contrario dejan el resultado dentro de int64.
      final subtotal =
          (await database
                  .customSelect(
                    'SELECT movement_subtotal(m.amount_cents) AS subtotal '
                    'FROM movements m WHERE ${filter.where}',
                    variables: filter.arguments,
                  )
                  .getSingle())
              .readNullable<int>('subtotal');
      if (subtotal == null) {
        throw const MovementFailure('El subtotal excede el rango int64.');
      }
      final rows = await _pageRecords(filter, after, limit + 1);
      final hasMore = rows.length > limit;
      final visible = hasMore ? rows.sublist(0, limit) : rows;
      return MovementPage(
        records: visible,
        subtotalCents: subtotal,
        nextCursor: hasMore
            ? MovementCursor(visible.last.data.valueDate, visible.last.id)
            : null,
      );
    });
  }

  void _validateLimit(int limit) {
    if (limit < 1 || limit > 500) {
      throw const MovementFailure('Tamaño de página inválido.');
    }
  }

  _MovementFilter _filter({
    required ValueDate? from,
    required ValueDate? until,
    String? accountId,
    String? categoryId,
    MovementCategoryScope categoryScope = MovementCategoryScope.direct,
    bool unclassifiedOnly = false,
    String? concept,
    bool openPeriod = false,
    bool importedOnly = false,
    String? batchId,
  }) {
    if ((from != null && until != null && until.compareTo(from) <= 0) ||
        (!openPeriod &&
            (from == null ||
                until == null && !from.value.startsWith('9999-'))) ||
        (unclassifiedOnly && categoryId != null)) {
      throw const MovementFailure('Rango o filtro de categoría inválidos.');
    }
    final clauses = <String>[];
    final args = <Variable>[];
    if (from != null) {
      clauses.add('m.value_date>=?');
      args.add(Variable(from.value));
    }
    if (until != null) {
      clauses.add('m.value_date<?');
      args.add(Variable(until.value));
    }
    if (accountId != null) {
      clauses.add('m.account_id=?');
      args.add(Variable(accountId));
    }
    if (categoryId != null) {
      clauses.add(
        categoryScope == MovementCategoryScope.direct
            ? 'm.category_id=?'
            : '''m.category_id IN (WITH RECURSIVE branch(id) AS (
SELECT id FROM categories WHERE id=?
UNION ALL SELECT c.id FROM categories c JOIN branch b ON c.parent_id=b.id
) SELECT id FROM branch)''',
      );
      args.add(Variable(categoryId));
    }
    if (unclassifiedOnly) clauses.add('m.category_id IS NULL');
    if (importedOnly) clauses.add('m.import_row_id IS NOT NULL');
    if (batchId != null) {
      clauses.add(
        'm.import_row_id IN (SELECT id FROM import_rows WHERE batch_id=?)',
      );
      args.add(Variable(batchId));
    }
    if (concept != null && concept.trim().isNotEmpty) {
      clauses.add('instr(movement_search_key(m.concept),?)>0');
      args.add(Variable(conceptSearchKey(concept.trim())));
    }
    return _MovementFilter(
      clauses.isEmpty ? '1=1' : clauses.join(' AND '),
      args,
    );
  }

  Future<List<MovementRecord>> _pageRecords(
    _MovementFilter filter,
    MovementCursor? after,
    int limit,
  ) async {
    var where = filter.where;
    final args = [...filter.arguments];
    if (after != null) {
      where += ' AND (m.value_date<? OR (m.value_date=? AND m.id>?))';
      args.addAll([
        Variable(after.valueDate.value),
        Variable(after.valueDate.value),
        Variable(after.id),
      ]);
    }
    args.add(Variable(limit));
    return (await database
            .customSelect(
              '$_select WHERE $where ORDER BY m.value_date DESC,m.id ASC LIMIT ?',
              variables: args,
            )
            .get())
        .map(_read)
        .toList();
  }
}

final class _MovementFilter {
  const _MovementFilter(this.where, this.arguments);
  final String where;
  final List<Variable> arguments;
}
