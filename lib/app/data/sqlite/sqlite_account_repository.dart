import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../features/wealth/wealth.dart';
import 'local_database.dart';
import 'schema_policy.dart';

final class SqliteAccountRepository implements AccountRepository {
  SqliteAccountRepository(this.database);
  final LocalDatabase database;
  String _now() => DateTime.fromMillisecondsSinceEpoch(
    DateTime.now().millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();
  void _name(String name) {
    if (name.trim().isEmpty) {
      throw const AccountFailure('El nombre no puede estar vacío.');
    }
  }

  AccountRecord _record(QueryRow r) => AccountRecord(
    id: r.read<String>('id'),
    name: r.read<String>('name'),
    kind: AccountKind.values.byName(r.read<String>('kind')),
    activeFrom: Month.parse(r.read<String>('active_from')),
    activeThrough: r.readNullable<String>('active_through') == null
        ? null
        : Month.parse(r.read<String>('active_through')),
    liquidity: r.data['liquidity'] == null
        ? null
        : Liquidity.values.byName(r.read<String>('liquidity')),
  );
  @override
  Future<AccountRecord?> get(String id) async {
    final rows = await database
        .customSelect(
          'SELECT * FROM accounts WHERE id=?',
          variables: [Variable(id)],
        )
        .get();
    return rows.isEmpty ? null : _record(rows.single);
  }

  Future<AccountRecord> _require(String id) async =>
      await get(id) ?? (throw const AccountFailure('La ficha no existe.'));
  Future<void> _coverage() async {
    if ((await database.customSelect(accountCoverageErrors).get()).isNotEmpty) {
      throw const AccountFailure(
        'La liquidez debe cubrir toda la vigencia sin huecos ni solapes.',
      );
    }
  }

  @override
  Future<List<AccountRecord>> listForMonth(Month month) async {
    await _coverage();
    return (await database.customSelect(
      '''SELECT a.*,p.liquidity FROM accounts a
LEFT JOIN account_liquidity_periods p ON p.account_id=a.id AND p.from_month<=? AND (p.until_month IS NULL OR p.until_month>?)
WHERE a.active_from<=? AND (a.active_through IS NULL OR a.active_through>=?) ORDER BY a.name,a.id''',
      variables: List.generate(4, (_) => Variable(month.value)),
    ).get()).map(_record).toList();
  }

  @override
  Future<List<LiquidityPeriod>> history(String id) async {
    await _require(id);
    return (await database
            .customSelect(
              'SELECT * FROM account_liquidity_periods WHERE account_id=? ORDER BY from_month',
              variables: [Variable(id)],
            )
            .get())
        .map(
          (r) => LiquidityPeriod(
            id: r.read<String>('id'),
            from: Month.parse(r.read<String>('from_month')),
            until: r.readNullable<String>('until_month') == null
                ? null
                : Month.parse(r.read<String>('until_month')),
            liquidity: Liquidity.values.byName(r.read<String>('liquidity')),
          ),
        )
        .toList();
  }

  Future<void> _insert(
    String account,
    Month from,
    Month? until,
    Liquidity liquidity,
  ) async {
    final now = _now();
    await database.customStatement(
      'INSERT INTO account_liquidity_periods VALUES(?,?,?,?,?,?,?)',
      [
        const Uuid().v4(),
        account,
        from.value,
        until?.value,
        liquidity.name,
        now,
        now,
      ],
    );
  }

  @override
  Future<AccountRecord> create({
    required String name,
    required AccountKind kind,
    required Month activeFrom,
    Month? activeThrough,
    Liquidity? liquidity,
  }) => database.transaction(() async {
    _name(name);
    if ((kind == AccountKind.debt) != (liquidity == null)) {
      throw const AccountFailure(
        'Los activos requieren liquidez y las deudas no la admiten.',
      );
    }
    if (activeThrough != null && activeThrough.compareTo(activeFrom) < 0) {
      throw const AccountFailure('La baja no puede preceder al alta.');
    }
    final id = const Uuid().v4(), now = _now();
    await database.customStatement(
      'INSERT INTO accounts VALUES(?,?,?,?,?,?,?)',
      [id, name, kind.name, activeFrom.value, activeThrough?.value, now, now],
    );
    if (liquidity != null) {
      await _insert(id, activeFrom, activeThrough?.next, liquidity);
    }
    await _coverage();
    return (await get(id))!;
  });
  @override
  Future<void> rename(String id, String name) => database.transaction(() async {
    _name(name);
    final old = await _require(id);
    if (old.name == name) return;
    await database.customStatement(
      'UPDATE accounts SET name=?,updated_at=? WHERE id=?',
      [name, _now(), id],
    );
  });
  @override
  Future<void> close(String id, Month activeThrough) => database.transaction(
    () async {
      await _coverage();
      final a = await _require(id);
      if (a.activeThrough?.value == activeThrough.value) return;
      if (a.activeThrough != null) {
        throw const AccountFailure(
          'La ficha ya está dada de baja; no puede reutilizarse.',
        );
      }
      if (activeThrough.compareTo(a.activeFrom) < 0) {
        throw const AccountFailure('La baja no puede preceder al alta.');
      }
      // Los repositorios futuros añaden también triggers de protección de referencias.
      final tables =
          (await database
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type='table'",
                  )
                  .get())
              .map((r) => r.read<String>('name'))
              .toSet();
      if (tables.contains('movements') &&
          (await database
                  .customSelect(
                    "SELECT 1 FROM movements WHERE account_id=? AND substr(value_date,1,7)>? LIMIT 1",
                    variables: [
                      Variable(id),
                      Variable(activeThrough.value.substring(0, 7)),
                    ],
                  )
                  .get())
              .isNotEmpty) {
        throw const AccountFailure(
          'La baja dejaría movimientos fuera de vigencia.',
        );
      }
      if (tables.contains('wealth_values') &&
          tables.contains('wealth_snapshots') &&
          (await database
                  .customSelect(
                    'SELECT 1 FROM wealth_values v JOIN wealth_snapshots s ON s.id=v.snapshot_id WHERE v.account_id=? AND s.month>? LIMIT 1',
                    variables: [Variable(id), Variable(activeThrough.value)],
                  )
                  .get())
              .isNotEmpty) {
        throw const AccountFailure('La baja dejaría fotos fuera de vigencia.');
      }
      final periods = await history(id);
      for (final p in periods) {
        if (p.from.compareTo(activeThrough) > 0) {
          await database.customStatement(
            'DELETE FROM account_liquidity_periods WHERE id=?',
            [p.id],
          );
        } else if (p.until == null || p.until!.compareTo(activeThrough) > 0) {
          await database.customStatement(
            'UPDATE account_liquidity_periods SET until_month=?,updated_at=? WHERE id=?',
            [activeThrough.next?.value, _now(), p.id],
          );
        }
      }
      await database.customStatement(
        'UPDATE accounts SET active_through=?,updated_at=? WHERE id=?',
        [activeThrough.value, _now(), id],
      );
      await _coverage();
    },
  );
  @override
  Future<void> changeLiquidity(String id, Month from, Liquidity liquidity) =>
      database.transaction(() async {
        final periods = await history(id);
        final matching = periods.where(
          (p) =>
              p.from.compareTo(from) <= 0 &&
              (p.until == null || p.until!.compareTo(from) > 0),
        );
        if (matching.isEmpty) {
          throw const AccountFailure(
            'El mes no tiene una clasificación vigente.',
          );
        }
        await _replace(id, from, matching.single.until, liquidity);
      });
  @override
  Future<void> correctHistoricalLiquidity(
    String id,
    Month from,
    Month? until,
    Liquidity liquidity,
  ) => database.transaction(() => _replace(id, from, until, liquidity));
  Future<void> _replace(
    String id,
    Month from,
    Month? until,
    Liquidity liquidity,
  ) async {
    final a = await _require(id);
    final end = a.activeThrough?.next;
    until ??= end;
    if (a.kind == AccountKind.debt ||
        from.compareTo(a.activeFrom) < 0 ||
        (a.activeThrough != null && from.compareTo(a.activeThrough!) > 0) ||
        (end != null && (until == null || until.compareTo(end) > 0)) ||
        (until != null && until.compareTo(from) <= 0)) {
      throw const AccountFailure(
        'Intervalo de liquidez fuera de la vigencia del activo.',
      );
    }
    final periods = await history(id);
    final affected = periods
        .where(
          (p) =>
              (until == null || p.from.compareTo(until) < 0) &&
              (p.until == null || p.until!.compareTo(from) > 0),
        )
        .toList();
    if (affected.length == 1 && affected.single.liquidity == liquidity) return;
    for (final p in affected) {
      await database.customStatement(
        'DELETE FROM account_liquidity_periods WHERE id=?',
        [p.id],
      );
    }
    for (final p in affected) {
      if (p.from.compareTo(from) < 0) {
        await _insert(id, p.from, from, p.liquidity);
      }
      if (until != null && (p.until == null || p.until!.compareTo(until) > 0)) {
        await _insert(id, until, p.until, p.liquidity);
      }
    }
    await _insert(id, from, until, liquidity);
    await _coverage();
  }
}
