import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart'
    hide WealthSnapshot;
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/wealth_management_factory.dart';
import 'package:myautofinance/features/movements/movements.dart'
    show MovementInput, ValueDate;
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  test('EUR exactos: vacío, cero, coma/punto y límite INTEGER de SQLite', () {
    expect(parseWealthAmount('  '), isNull);
    expect(parseWealthAmount('0'), 0);
    expect(parseWealthAmount(' 001,01 '), 101);
    expect(parseWealthAmount('6200.5'), 620050);
    expect(parseWealthAmount('0,29'), 29);
    const maximum = 9223372036854775807;
    expect(parseWealthAmount('92233720368547758,07'), maximum);
    expect(wealthAmountText(maximum), '92233720368547758,07');
    for (final invalid in [
      '-0',
      '-1',
      '−2',
      '+2',
      '1,001',
      '1.000,00',
      'NaN',
      '1e2',
      '0,',
      '.5',
      '92233720368547758,08',
      '9999999999999999999999999',
    ]) {
      expect(
        () => parseWealthAmount(invalid),
        throwsA(isA<WealthFailure>()),
        reason: invalid,
      );
    }
  });

  late LocalDatabase db;
  late WealthManagement service;
  late Directory directory;
  late LocalDatabaseStore store;
  final january = Month(2026, 1), february = Month(2026, 2);
  late String mainId, savingsId, portfolioId, debtId;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('wealth-photo-');
    store = LocalDatabaseStore(supportDirectory: () async => directory);
    db = await store.open();
    service = createWealthManagement(database: db);
    Future<String> create(
      String name,
      AccountKind kind,
      Liquidity? liquidity,
    ) async => (await service.create(
      name: name,
      kind: kind,
      activeFrom: january,
      liquidity: liquidity,
    )).account.id;
    mainId = await create(
      'Cuenta principal',
      AccountKind.account,
      Liquidity.liquid,
    );
    savingsId = await create(
      'Cuenta de ahorro',
      AccountKind.account,
      Liquidity.liquid,
    );
    portfolioId = await create(
      'Cartera',
      AccountKind.portfolio,
      Liquidity.medium,
    );
    debtId = await create('Deuda familiar', AccountKind.debt, null);
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  Map<String, int?> values(
    int? main,
    int? savings,
    int? portfolio,
    int? debt,
  ) => {mainId: main, savingsId: savings, portfolioId: portfolio, debtId: debt};

  test(
    'Caso D: parcial, completar con cero, corregir y reabrir sin arrastre',
    () async {
      await service.savePhoto(january, values(600000, 300000, 1000000, 500000));
      await SqliteMovementRepository(db).create(
        MovementInput(
          accountId: mainId,
          valueDate: ValueDate(2026, 2, 20),
          concept: 'Ingreso sintético posterior al día 1',
          amountCents: 1000000,
        ),
      );
      final absent = await service.photos.read(february);
      expect(absent.values, isEmpty);
      expect(absent.status, WealthSnapshotStatus.absent);
      final before = await db.readState();
      final partial = await service.savePhoto(
        february,
        values(620000, null, null, 480000),
      );
      expect((await db.readState()).revision, before.revision + 1);
      expect(partial.month.value, '2026-02-01');
      expect(partial.status, WealthSnapshotStatus.incomplete);
      expect(partial.pending.map((a) => a.id).toSet(), {
        savingsId,
        portfolioId,
      });
      expect(WealthReading.fromSnapshot(partial).totals, isNull);
      final originalId = partial.values
          .firstWhere((v) => v.account.id == mainId)
          .id;
      final complete = await service.savePhoto(
        february,
        values(620000, 0, 1050000, 480000),
      );
      expect(complete.status, WealthSnapshotStatus.complete);
      expect(complete.snapshotId, partial.snapshotId);
      expect(
        WealthReading.fromSnapshot(complete).totals!.netWorthCents,
        1190000,
      );
      final corrected = await service.savePhoto(
        february,
        values(630000, 0, 1050000, 480000),
      );
      expect(
        corrected.values.firstWhere((v) => v.account.id == mainId).id,
        originalId,
      );
      expect(
        WealthReading.fromSnapshot(corrected).totals!.netWorthCents,
        1200000,
      );
      final state = await db.readState();
      await service.savePhoto(february, values(630000, 0, 1050000, 480000));
      expect((await db.readState()).revision, state.revision);
      await store.close();
      db = await store.open();
      service = createWealthManagement(database: db);
      expect((await service.readMonth(january)).totals!.netWorthCents, 1400000);
      final persisted = await service.photos.read(february);
      expect(
        persisted.values.firstWhere((v) => v.account.id == mainId).id,
        originalId,
      );
      expect(
        WealthReading.fromSnapshot(persisted).totals!.netWorthCents,
        1200000,
      );
      expect((await service.photos.read(Month(2026, 3))).values, isEmpty);
    },
  );

  test(
    'Vaciar un valor vuelve a pendiente; todo vacío es ausencia y no cero',
    () async {
      await service.savePhoto(february, values(100, 0, 0, 0));
      final partial = await service.savePhoto(february, values(null, 0, 0, 0));
      expect(partial.pending.single.id, mainId);
      expect(partial.status, WealthSnapshotStatus.incomplete);
      final empty = await service.savePhoto(
        february,
        values(null, null, null, null),
      );
      expect(empty.status, WealthSnapshotStatus.absent);
      expect(empty.values, isEmpty);
      expect(empty.pending, hasLength(4));
      expect(WealthReading.fromSnapshot(empty).totals, isNull);
    },
  );

  test(
    'Fallo de la última escritura revierte cambios, borrados y revisión',
    () async {
      final original = await service.savePhoto(
        february,
        values(100, 0, 200, 300),
      );
      final state = await db.readState();
      await db.customStatement('''CREATE TEMP TRIGGER photo_failure
      BEFORE UPDATE ON wealth_values WHEN NEW.account_id='$debtId'
      BEGIN SELECT RAISE(ABORT, 'fallo sintético'); END''');
      await expectLater(
        service.savePhoto(february, values(999, null, 777, 888)),
        throwsA(anything),
      );
      final unchanged = await service.photos.read(february);
      expect({
        for (final v in unchanged.values) v.account.id: v.amountCents,
      }, values(100, 0, 200, 300));
      expect(
        unchanged.values.map((v) => v.id),
        original.values.map((v) => v.id),
      );
      expect((await db.readState()).revision, state.revision);
      await db.customStatement('DROP TRIGGER photo_failure');
      final retry = await service.savePhoto(
        february,
        values(999, null, 777, 888),
      );
      expect(retry.values, hasLength(3));
      expect(retry.pending.single.id, savingsId);
    },
  );

  test('Fallo de lectura final revierte incluso una foto nueva', () async {
    final state = await db.readState();
    final failing = WealthManagement(
      accounts: service.accounts,
      photos: _FailFinalRead(service.photos),
      unitOfWork: db,
    );
    await expectLater(
      failing.savePhoto(february, values(1, 2, 3, 4)),
      throwsA(isA<WealthFailure>()),
    );
    final unchanged = await service.photos.read(february);
    expect(unchanged.snapshotId, isNull);
    expect(unchanged.values, isEmpty);
    expect((await db.readState()).revision, state.revision);
  });

  test('Vigencia, clasificación mensual y catálogo cambiado rechazan borradores obsoletos', () async {
    await service.accounts.changeLiquidity(
      portfolioId,
      february,
      Liquidity.liquid,
    );
    await service.accounts.close(debtId, february);
    final future = await service.create(
      name: 'Cuenta futura',
      kind: AccountKind.account,
      activeFrom: Month(2026, 3),
      activeThrough: Month(2026, 4),
      liquidity: Liquidity.illiquid,
    );
    final photo = await service.savePhoto(february, values(0, 0, 0, 0));
    expect(
      photo.values
          .firstWhere((v) => v.account.id == portfolioId)
          .account
          .liquidity,
      Liquidity.liquid,
    );
    expect(photo.values.any((v) => v.account.id == future.account.id), isFalse);
    expect(
      (await service.photos.read(january)).pending
          .firstWhere((a) => a.id == portfolioId)
          .liquidity,
      Liquidity.medium,
    );
    expect(
      (await service.photos.read(Month(2026, 3))).pending
          .any((a) => a.id == debtId),
      isFalse,
    );
    expect(
      (await service.photos.read(Month(2026, 4))).pending
          .any((a) => a.id == future.account.id),
      isTrue,
    );
    expect(
      (await service.photos.read(Month(2026, 5))).pending
          .any((a) => a.id == future.account.id),
      isFalse,
    );
    await service.create(
      name: 'Alta concurrente',
      kind: AccountKind.debt,
      activeFrom: february,
    );
    final state = await db.readState();
    await expectLater(
      service.savePhoto(february, values(9, 9, 9, 9)),
      throwsA(isA<WealthFailure>()),
    );
    expect((await db.readState()).revision, state.revision);
    expect(
      (await service.photos.read(february)).values
          .every((v) => v.amountCents == 0),
      isTrue,
    );
    final negative = {
      for (final a in (await service.photos.read(february)).pending) a.id: 0,
      ...values(0, -1, 0, 0),
    };
    await expectLater(
      service.savePhoto(february, negative),
      throwsA(isA<WealthFailure>()),
    );
    expect((await db.readState()).revision, state.revision);
  });
}

class _FailFinalRead implements WealthRepository {
  _FailFinalRead(this.delegate);
  final WealthRepository delegate;
  int reads = 0;
  @override
  Future<WealthSnapshot> read(Month month) {
    if (++reads == 2) throw const WealthFailure('fallo sintético de lectura');
    return delegate.read(month);
  }

  @override
  Future<List<WealthSnapshot>> readYear(int year) => delegate.readYear(year);
  @override
  Future<void> prepare(Month month) => delegate.prepare(month);
  @override
  Future<void> setValue(Month month, String id, int cents) =>
      delegate.setValue(month, id, cents);
  @override
  Future<void> deleteValue(Month month, String id) =>
      delegate.deleteValue(month, id);
  @override
  Future<void> deleteSnapshot(Month month) => delegate.deleteSnapshot(month);
}
