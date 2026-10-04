import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_wealth_repository.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  late LocalDatabase db;
  late WealthManagement service;
  late Directory directory;
  late LocalDatabaseStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('account-management-');
    store = LocalDatabaseStore(supportDirectory: () async => directory);
    db = await store.open();
    service = WealthManagement(
      accounts: SqliteAccountRepository(db),
      photos: SqliteWealthRepository(db),
      unitOfWork: db,
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  test(
    'Alta de tres tipos, vigencia inclusiva e identidades independientes',
    () async {
      for (final kind in AccountKind.values) {
        final result = await service.create(
          name: ' Ficha sintética ',
          kind: kind,
          activeFrom: Month(2026, 2),
          activeThrough: Month(2026, 2),
          liquidity: kind == AccountKind.debt ? null : Liquidity.medium,
        );
        expect(result.account.name, 'Ficha sintética');
        expect(result.history.length, kind == AccountKind.debt ? 0 : 1);
      }
      expect((await service.catalog()).map((a) => a.id).toSet().length, 3);
      expect(await service.accounts.listForMonth(Month(2026, 1)), isEmpty);
      expect(await service.accounts.listForMonth(Month(2026, 2)), hasLength(3));
      expect(await service.accounts.listForMonth(Month(2026, 3)), isEmpty);
      final state = await db.readState();
      await expectLater(
        service.create(
          name: 'Inválida',
          kind: AccountKind.debt,
          activeFrom: Month(2026, 2),
          activeThrough: Month(2026, 1),
        ),
        throwsA(isA<AccountFailure>()),
      );
      expect((await db.readState()).revision, state.revision);
    },
  );
  test('Baja rechazada revierte nombre y conserva fotos e historial; cierre y renombrado conservan identidad', () async {
    final created = await service.create(
      name: 'Original',
      kind: AccountKind.account,
      activeFrom: Month(2026, 1),
      liquidity: Liquidity.liquid,
    );
    final id = created.account.id;
    await service.accounts.changeLiquidity(
      id,
      Month(2026, 2),
      Liquidity.medium,
    );
    await service.photos.setValue(Month(2026, 3), id, 12500);
    final revision = (await db.readState()).revision;
    await expectLater(
      service.edit(id, name: 'Borrador', activeThrough: Month(2026, 2)),
      throwsA(isA<AccountFailure>()),
    );
    expect((await service.details(id)).account.name, 'Original');
    expect((await service.details(id)).history, hasLength(2));
    expect(
      (await service.photos.read(Month(2026, 3))).status,
      WealthSnapshotStatus.complete,
    );
    expect((await db.readState()).revision, revision);
    final closed = await service.edit(
      id,
      name: 'Cerrada',
      activeThrough: Month(2026, 3),
    );
    expect(closed.account.id, id);
    expect((await db.readState()).revision, revision + 1);
    await service.edit(id, name: 'Renombrada', activeThrough: Month(2026, 3));
    await expectLater(
      service.edit(id, name: 'Reabrir', activeThrough: null),
      throwsA(isA<AccountFailure>()),
    );
    expect((await service.details(id)).account.name, 'Renombrada');
    expect((await service.catalog()).single.id, id);
    expect(await service.accounts.listForMonth(Month(2026, 4)), isEmpty);
  });
}
