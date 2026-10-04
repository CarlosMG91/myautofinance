import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart'
    show LocalDatabase;
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/wealth_management_factory.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  late LocalDatabase database;
  late WealthManagement management;
  late WealthController controller;
  final january = Month(2026, 1), february = Month(2026, 2);

  Future<AccountRecord> create(
    String name, {
    AccountKind kind = AccountKind.account,
    Liquidity liquidity = Liquidity.liquid,
    Month? from,
    Month? through,
  }) => management.accounts.create(
    name: name,
    kind: kind,
    activeFrom: from ?? january,
    activeThrough: through,
    liquidity: kind == AccountKind.debt ? null : liquidity,
  );

  Future<List<AccountRecord>> caseD({bool completeFebruary = false}) async {
    final accounts = [
      await create('Cuenta principal'),
      await create('Cuenta de ahorro'),
      await create(
        'Cartera',
        kind: AccountKind.portfolio,
        liquidity: Liquidity.medium,
      ),
      await create('Deuda familiar', kind: AccountKind.debt),
    ];
    final amounts = [600000, 300000, 1000000, 500000];
    for (var i = 0; i < accounts.length; i++) {
      await management.photos.setValue(january, accounts[i].id, amounts[i]);
    }
    if (completeFebruary) {
      final amounts = [620000, 0, 1050000, 480000];
      for (var i = 0; i < accounts.length; i++) {
        await management.photos.setValue(february, accounts[i].id, amounts[i]);
      }
    }
    return accounts;
  }

  setUp(() {
    database = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
    management = createWealthManagement(database: database);
    controller = WealthController(loadManagement: () async => management);
  });
  tearDown(() async => database.close());

  test(
    'Caso D: magnitudes, parcial, cero y corrección del mismo mes',
    () async {
      final accounts = await caseD();
      final januaryReading = await controller.readMonth(january);
      final totals = januaryReading.totals!;
      expect(januaryReading.status, WealthSnapshotStatus.complete);
      expect(totals.liquidAssetsCents, 900000);
      expect(totals.mediumAssetsCents, 1000000);
      expect(totals.illiquidAssetsCents, 0);
      expect(totals.assetsCents, 1900000);
      expect(totals.debtsCents, 500000);
      expect(totals.netWorthCents, 1400000);
      expect(januaryReading.pending, isEmpty);

      var reading = await controller.readMonth(february);
      expect(reading.status, WealthSnapshotStatus.absent);
      expect(reading.totals, isNull);
      expect(reading.liquidAssetsCents, isNull);
      expect(reading.pending, hasLength(4));
      await management.photos.setValue(february, accounts[0].id, 620000);
      await management.photos.setValue(february, accounts[3].id, 480000);
      reading = await controller.readMonth(february);
      expect(reading.status, WealthSnapshotStatus.incomplete);
      expect(reading.values, hasLength(2));
      expect(reading.totals, isNull);
      expect(reading.liquidAssetsCents, isNull);
      expect(
        reading.pending.map((a) => a.id),
        unorderedEquals([accounts[1].id, accounts[2].id]),
      );

      await management.photos.setValue(february, accounts[1].id, 0);
      await management.photos.setValue(february, accounts[2].id, 1050000);
      reading = await controller.readMonth(february);
      expect(reading.status, WealthSnapshotStatus.complete);
      expect(reading.liquidAssetsCents, 620000);
      expect(reading.totals!.mediumAssetsCents, 1050000);
      expect(reading.totals!.assetsCents, 1670000);
      expect(reading.totals!.debtsCents, 480000);
      expect(reading.totals!.netWorthCents, 1190000);
      final snapshotId = reading.snapshot.snapshotId;
      await management.photos.setValue(february, accounts[0].id, 630000);
      reading = await controller.readMonth(february);
      expect(reading.month.value, '2026-02-01');
      expect(reading.snapshot.snapshotId, snapshotId);
      expect(reading.liquidAssetsCents, 630000);
      expect(reading.totals!.netWorthCents, 1200000);
      expect(
        (await controller.readMonth(january)).totals!.netWorthCents,
        1400000,
      );
      expect(januaryReading.totals!.netWorthCents, 1400000);
    },
  );

  test(
    'Liquidez efectiva e histórica cambia clasificación, no valores',
    () async {
      final accounts = await caseD(completeFebruary: true);
      final portfolio = accounts[2].id;
      await management.accounts.changeLiquidity(
        portfolio,
        february,
        Liquidity.liquid,
      );
      var reading = await controller.readMonth(february);
      expect(reading.liquidAssetsCents, 1670000);
      expect(reading.totals!.mediumAssetsCents, 0);
      expect(reading.totals!.netWorthCents, 1190000);
      expect((await controller.readMonth(january)).liquidAssetsCents, 900000);
      await management.accounts.correctHistoricalLiquidity(
        portfolio,
        february,
        Month(2026, 3),
        Liquidity.medium,
      );
      reading = await controller.readMonth(february);
      expect(reading.liquidAssetsCents, 620000);
      expect(reading.totals!.mediumAssetsCents, 1050000);
      expect(reading.totals!.netWorthCents, 1190000);
      expect((await controller.readMonth(january)).liquidAssetsCents, 900000);
      expect((await controller.readMonth(Month(2026, 3))).totals, isNull);
    },
  );

  test(
    'Vigencia inclusiva exige altas y no exige bajas ni fichas futuras',
    () async {
      final account = await create(
        'Vigente',
        from: Month(2026, 3),
        through: Month(2026, 4),
      );
      expect((await controller.readMonth(february)).pending, isEmpty);
      for (final month in [Month(2026, 3), Month(2026, 4)]) {
        var reading = await controller.readMonth(month);
        expect(reading.status, WealthSnapshotStatus.absent);
        expect(reading.pending.single.id, account.id);
        await management.photos.setValue(month, account.id, 0);
        reading = await controller.readMonth(month);
        expect(reading.status, WealthSnapshotStatus.complete);
        expect(reading.totals!.assetsCents, 0);
      }
      final may = await controller.readMonth(Month(2026, 5));
      expect(may.status, WealthSnapshotStatus.absent);
      expect(may.pending, isEmpty);
      expect(may.totals, isNull);
    },
  );

  test('Ausente sin fichas y cabecera vacía nunca representan cero', () async {
    var reading = await controller.readMonth(january);
    expect(reading.status, WealthSnapshotStatus.absent);
    expect(reading.totals, isNull);
    expect(reading.pending, isEmpty);
    await management.photos.prepare(january);
    reading = await controller.readMonth(january);
    expect(reading.snapshot.snapshotId, isNotNull);
    expect(reading.status, WealthSnapshotStatus.absent);
    expect(reading.totals, isNull);
    final account = await create('Pendiente');
    reading = await controller.readMonth(january);
    expect(reading.pending.single.id, account.id);
    expect(reading.totals, isNull);
  });

  test('Todas las liquideces, céntimos exactos y neto negativo', () async {
    final amounts = [101, 202, 303];
    for (var i = 0; i < Liquidity.values.length; i++) {
      final a = await create(
        'Activo $i',
        kind: i == 0 ? AccountKind.account : AccountKind.portfolio,
        liquidity: Liquidity.values[i],
      );
      await management.photos.setValue(january, a.id, amounts[i]);
    }
    final debt = await create('Deuda', kind: AccountKind.debt);
    await management.photos.setValue(january, debt.id, 1000);
    final reading = await controller.readMonth(january);
    expect(reading.liquidAssetsCents, 101);
    expect(reading.totals!.mediumAssetsCents, 202);
    expect(reading.totals!.illiquidAssetsCents, 303);
    expect(reading.totals!.assetsCents, 606);
    expect(reading.totals!.debtsCents, 1000);
    expect(reading.totals!.netWorthCents, -394);
    await management.photos.deleteValue(january, debt.id);
    final partial = await controller.readMonth(january);
    expect(partial.status, WealthSnapshotStatus.incomplete);
    expect(partial.totals, isNull);
    expect(partial.liquidAssetsCents, isNull);
  });

  test(
    'Año: doce meses independientes, revisión intacta y calendario',
    () async {
      await caseD(completeFebruary: true);
      final before = await database.readState();
      final year = await controller.readYear(2026);
      expect(year, hasLength(12));
      expect(
        year.map((r) => r.month.value),
        List.generate(12, (i) => Month(2026, i + 1).value),
      );
      expect(year[0].totals!.netWorthCents, 1400000);
      expect(year[1].totals!.netWorthCents, 1190000);
      for (final month in year.skip(2)) {
        expect(month.status, WealthSnapshotStatus.absent);
        expect(month.totals, isNull);
        expect(month.values, isEmpty);
        expect(month.pending, hasLength(4));
      }
      expect(() => year.clear(), throwsUnsupportedError);
      expect((await database.readState()).revision, before.revision);
      await expectLater(controller.readYear(0), throwsA(isA<AccountFailure>()));
      expect((await controller.readYear(9999)).last.month.value, '9999-12-01');
    },
  );

  test(
    'Controlador vuelve a resolver la base tras reemplazar la sesión',
    () async {
      await caseD();
      expect(
        (await controller.readMonth(january)).totals!.netWorthCents,
        1400000,
      );
      await database.close();
      database = LocalDatabase(
        NativeDatabase.memory(setup: configureConnection),
      );
      management = createWealthManagement(database: database);
      expect((await controller.readMonth(january)).totals, isNull);
      expect(
        (await controller.readYear(2026)).every((r) => r.totals == null),
        isTrue,
      );
    },
  );
}
