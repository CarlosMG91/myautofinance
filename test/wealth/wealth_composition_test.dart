import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/local_backup_session.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_wealth_repository.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late LocalBackupSession session;
  late WealthManagement management;
  late WealthController controller;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('wealth-composition-');
    session = LocalBackupSession(supportDirectory: () async => directory);
    expect(await session.open(), isTrue);
    management = await session.wealth();
    controller = WealthController(loadManagement: session.wealth);
  });
  tearDown(() async {
    await session.store.close();
    session.controller.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'Un controlador existente consulta la base reemplazada al restaurar',
    () async {
      final account = await management.accounts.create(
        name: 'Antes de restaurar',
        kind: AccountKind.account,
        activeFrom: Month(2026, 1),
        liquidity: Liquidity.liquid,
      );
      await session.controller.create();
      expect(session.controller.error, isNull);
      final backup = session.controller.listing!.entries.single.backupId;
      await management.accounts.rename(account.id, 'Cambio posterior');
      expect(
        (await controller.details(account.id)).account.name,
        'Cambio posterior',
      );
      await session.controller.restore(backup, confirmed: true);
      expect(session.controller.error, isNull);
      expect(
        (await controller.details(account.id)).account.name,
        'Antes de restaurar',
      );
    },
  );

  test(
    'Catálogo completo y detalle cerrado conservan identidad e historial',
    () async {
      expect(management.accounts, isA<SqliteAccountRepository>());
      expect(management.photos, isA<SqliteWealthRepository>());
      expect(
        (management.accounts as SqliteAccountRepository).database,
        same((management.photos as SqliteWealthRepository).database),
      );
      final old = await management.accounts.create(
        name: 'Cuenta sintética',
        kind: AccountKind.account,
        activeFrom: Month(2026, 1),
        liquidity: Liquidity.liquid,
      );
      await management.accounts.changeLiquidity(
        old.id,
        Month(2026, 2),
        Liquidity.medium,
      );
      await management.photos.setValue(Month(2026, 2), old.id, 0);
      await management.accounts.close(old.id, Month(2026, 3));
      final future = await management.accounts.create(
        name: 'Cuenta sintética',
        kind: AccountKind.portfolio,
        activeFrom: Month(2027, 1),
        liquidity: Liquidity.illiquid,
      );
      final debt = await management.accounts.create(
        name: 'Deuda sintética',
        kind: AccountKind.debt,
        activeFrom: Month(2026, 4),
      );
      final db = await session.store.open();
      final before = await db.readState();
      final catalog = await controller.catalog();
      expect(
        catalog.map((a) => a.id),
        unorderedEquals([old.id, future.id, debt.id]),
      );
      expect(catalog.every((a) => a.liquidity == null), isTrue);
      final detail = await controller.details(old.id);
      expect(detail.account.activeThrough!.value, '2026-03-01');
      expect(detail.history.map((p) => p.liquidity), [
        Liquidity.liquid,
        Liquidity.medium,
      ]);
      expect(detail.history.last.until!.value, '2026-04-01');
      expect((await controller.details(debt.id)).history, isEmpty);
      await expectLater(
        controller.details('inexistente'),
        throwsA(isA<AccountFailure>()),
      );
      expect(
        (await management.accounts.listForMonth(Month(2026, 4)))
            .map((a) => a.id),
        [debt.id],
      );
      expect((await db.readState()).revision, before.revision);

      await session.store.close();
      final reopened = await controller.details(old.id);
      expect(
        reopened.history.map((p) => p.id),
        detail.history.map((p) => p.id),
      );
      final photo = await controller.month(Month(2026, 2));
      expect(photo.status, WealthSnapshotStatus.complete);
      expect(photo.values.single.amountCents, 0);
      expect(photo.values.single.account.id, old.id);
      expect(photo.values.single.account.liquidity, Liquidity.medium);
    },
  );

  test(
    'Fotos independientes: parcial, cero y doce consultas sin crear datos',
    () async {
      final a = await management.accounts.create(
        name: 'Activo',
        kind: AccountKind.account,
        activeFrom: Month(2026, 1),
        liquidity: Liquidity.liquid,
      );
      final d = await management.accounts.create(
        name: 'Pasivo',
        kind: AccountKind.debt,
        activeFrom: Month(2026, 1),
      );
      await management.photos.setValue(Month(2026, 1), a.id, 900000);
      var photo = await controller.month(Month(2026, 1));
      expect(photo.status, WealthSnapshotStatus.incomplete);
      expect(photo.pending.single.id, d.id);
      await management.photos.setValue(Month(2026, 1), d.id, 0);
      photo = await controller.month(Month(2026, 1));
      expect(photo.status, WealthSnapshotStatus.complete);
      final db = await session.store.open();
      final revision = (await db.readState()).revision;
      final year = await controller.year(2026);
      expect(year, hasLength(12));
      expect(year.first.snapshotId, photo.snapshotId);
      expect(
        year
            .skip(1)
            .every(
              (s) =>
                  s.status == WealthSnapshotStatus.absent &&
                  s.values.isEmpty &&
                  s.pending.length == 2,
            ),
        isTrue,
      );
      expect((await db.readState()).revision, revision);
      await expectLater(controller.year(0), throwsA(isA<AccountFailure>()));
    },
  );
}
