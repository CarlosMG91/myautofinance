import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../features/wealth/wealth.dart';
import 'local_database.dart' hide WealthSnapshot, WealthValue;
import 'sqlite_account_repository.dart';

final class SqliteWealthRepository implements WealthRepository {
  SqliteWealthRepository(this.database);
  final LocalDatabase database;

  @override
  Future<List<WealthSnapshot>> readYear(int year) {
    Month(year, 1); // Valida antes de abrir una transacción.
    return database.transaction(() async {
      final result = <WealthSnapshot>[];
      for (var month = 1; month <= 12; month++) {
        result.add(await read(Month(year, month)));
      }
      return List.unmodifiable(result);
    });
  }

  String _now() => DateTime.fromMillisecondsSinceEpoch(
    DateTime.now().millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();
  Future<String?> _snapshot(Month month) async {
    final rows = await database
        .customSelect(
          'SELECT id FROM wealth_snapshots WHERE month=?',
          variables: [Variable(month.value)],
        )
        .get();
    return rows.isEmpty ? null : rows.single.read<String>('id');
  }

  Future<String> _prepare(Month month) async {
    final old = await _snapshot(month);
    if (old != null) return old;
    final id = const Uuid().v4(), now = _now();
    await database.customStatement(
      'INSERT INTO wealth_snapshots VALUES(?,?,?,?)',
      [id, month.value, now, now],
    );
    return id;
  }

  @override
  Future<void> prepare(Month month) => database.writeTransaction(() async {
    await _prepare(month);
  });
  @override
  Future<void> setValue(Month month, String accountId, int amountCents) =>
      database.writeTransaction(() async {
        if (amountCents < 0) {
          throw const WealthFailure('La valoración debe ser no negativa.');
        }
        final accounts = await SqliteAccountRepository(database)
            .listForMonth(month);
        if (!accounts.any((a) => a.id == accountId)) {
          throw const WealthFailure(
            'La ficha no existe o no está vigente en ese mes.',
          );
        }
        final snapshot = await _prepare(month);
        final now = _now();
        await database.customStatement(
          '''INSERT INTO wealth_values VALUES(?,?,?,?,?,?)
ON CONFLICT(snapshot_id,account_id) DO UPDATE SET amount_cents=excluded.amount_cents,updated_at=excluded.updated_at
WHERE wealth_values.amount_cents<>excluded.amount_cents''',
          [const Uuid().v4(), snapshot, accountId, amountCents, now, now],
        );
      });
  @override
  Future<void> deleteValue(Month month, String accountId) =>
      database.writeTransaction(() async {
        await database.customStatement(
          'DELETE FROM wealth_values WHERE snapshot_id IN (SELECT id FROM wealth_snapshots WHERE month=?) AND account_id=?',
          [month.value, accountId],
        );
      });
  @override
  Future<void> deleteSnapshot(Month month) =>
      database.writeTransaction(() async {
        await database.customStatement(
          'DELETE FROM wealth_values WHERE snapshot_id IN (SELECT id FROM wealth_snapshots WHERE month=?)',
          [month.value],
        );
        await database.customStatement(
          'DELETE FROM wealth_snapshots WHERE month=?',
          [month.value],
        );
      });
  @override
  Future<WealthSnapshot> read(Month month) => database.writeTransaction(
    () async {
      final accounts = await SqliteAccountRepository(database)
          .listForMonth(month);
      final snapshot = await _snapshot(month);
      final rows = await database
          .customSelect(
            'SELECT * FROM wealth_values WHERE snapshot_id=?',
            variables: [Variable(snapshot ?? '')],
          )
          .get();
      final byAccount = {for (final r in rows) r.read<String>('account_id'): r};
      final values = <WealthValue>[], pending = <AccountRecord>[];
      for (final a in accounts) {
        final row = byAccount[a.id];
        if (row == null) {
          pending.add(a);
        } else {
          values.add(
            WealthValue(
              id: row.read<String>('id'),
              account: a,
              amountCents: row.read<int>('amount_cents'),
            ),
          );
        }
      }
      return WealthSnapshot(
        month: month,
        snapshotId: snapshot,
        status: values.isEmpty
            ? WealthSnapshotStatus.absent
            : pending.isNotEmpty
            ? WealthSnapshotStatus.incomplete
            : WealthSnapshotStatus.complete,
        values: values,
        pending: pending,
      );
    },
  );
}
