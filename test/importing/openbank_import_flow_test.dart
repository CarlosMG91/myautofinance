import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_wealth_repository.dart';
import 'package:myautofinance/app/import_factory.dart';
import 'package:myautofinance/app/openbank_import_factory.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/importing/presentation/import_controller.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

import 'openbank_reader_test.dart' show bankFixture;

class QueueBankSelector implements LocalFileSelector {
  final queue = <LocalFileSelection>[];
  @override
  Future<LocalFileSelection> select() async => queue.removeAt(0);
  void add(List<int> bytes, {String name = 'sintético.xls'}) => queue.add(
    LocalFileSelected(name: name, bytes: Uint8List.fromList(bytes)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalDatabase db;
  late ImportServices services;
  late ImportController c;
  late QueueBankSelector selector;
  late String account;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('openbank-synthetic-');
    db = LocalDatabase(
      NativeDatabase(
        File('${dir.path}/data.sqlite'),
        setup: configureConnection,
      ),
    );
    services = createImportServices(db);
    account = (await SqliteAccountRepository(db).create(
      name: 'Cuenta sintética',
      kind: AccountKind.account,
      activeFrom: Month(2026, 1),
      liquidity: Liquidity.liquid,
    )).id;
    await SqliteWealthRepository(db).setValue(Month(2026, 2), account, 76543);
    selector = QueueBankSelector();
    c = createOpenbankImportController(
      () async => services,
      selector: selector,
    );
  });
  tearDown(() async {
    c.dispose();
    await db.close();
    await dir.delete(recursive: true);
  });
  Future<void> select() => c.selectFile(approveReplacement: () async => true);
  Future<int> count(String t) async =>
      (await db.customSelect('SELECT count(*) AS n FROM $t').getSingle())
          .read<int>('n');
  Future<List<Object>> photos() async => [
    for (final t in [
      'accounts',
      'account_liquidity_periods',
      'wealth_snapshots',
      'wealth_values',
      'budgets',
    ])
      (await db.customSelect('SELECT * FROM $t ORDER BY rowid').get())
          .map((r) => r.data)
          .toList(),
  ];
  Future<void> bind() => c.bindAccount(
    const ImportAccountReference.selectedAccount(),
    id: account,
  );
  test('Selector real → lector en segundo plano → cuenta explícita → SQLite → repetición y reapertura; fotos intactas', () async {
    final before = await photos();
    selector.add(bankFixture());
    await select();
    expect(c.phase, ImportPhase.review);
    expect(c.canConfirm, isFalse);
    expect(c.review!.pendingReferences, hasLength(1));
    expect(await count('import_batches'), 0);
    await bind();
    expect(c.canConfirm, isTrue);
    await c.confirm();
    expect(c.phase, ImportPhase.imported);
    expect(await count('movements'), 4);
    expect(await count('budgets'), 0);
    expect(await photos(), before);
    final batch = (c.result as ImportConfirmed).batch;
    expect(batch.source, ImportSource.bankXls);
    final original = await services.history.listRows(batch.id);
    expect(original.items, hasLength(4));
    selector.add(bankFixture(), name: 'renombrado.xls');
    await select();
    expect(c.phase, ImportPhase.alreadyImported);
    expect(await count('movements'), 4);
    expect(await photos(), before);
    await db.close();
    db = LocalDatabase(
      NativeDatabase(
        File('${dir.path}/data.sqlite'),
        setup: configureConnection,
      ),
    );
    services = createImportServices(db);
    expect((await services.history.listRows(batch.id)).items, hasLength(4));
    expect(
      (await db
          .customSelect('SELECT * FROM movements WHERE category_id IS NULL')
          .get()),
      hasLength(4),
    );
    expect(await photos(), before);
  });
  test('Cancelación conserva revisión; cambio borra asignación y marcas; error no escribe', () async {
    selector.add(bankFixture());
    await select();
    await bind();
    final session = c.session;
    selector.queue.add(const LocalFileCancelled());
    await select();
    expect(c.session, same(session));
    expect(c.canConfirm, isTrue);
    selector.queue.add(
      const LocalFileFailed(LocalFileFailureCode.accessDenied),
    );
    await select();
    expect(c.session, same(session));
    expect(c.canConfirm, isTrue);
    selector.add(
      latin1.encode(
        latin1.decode(bankFixture()).replaceFirst('1.200,00', '0,00'),
      ),
    );
    await select();
    expect(c.phase, ImportPhase.error);
    expect(c.canConfirm, isFalse);
    expect(c.review!.bindings.accounts, isEmpty);
    expect(await count('movements'), 0);
    expect(await count('import_batches'), 0);
  });
  test('Otro archivo solapado exige todos los avisos; conserva duplicados legítimos y fotos', () async {
    final before = await photos();
    selector.add(bankFixture());
    await select();
    await bind();
    await c.confirm();
    selector.add([...bankFixture(), 10]);
    await select();
    await bind();
    expect(c.review!.overlaps, isNotEmpty);
    expect(c.canConfirm, isFalse);
    for (final overlap in c.review!.overlaps) {
      c.markOverlap(overlap.key, true);
    }
    expect(c.canConfirm, isTrue);
    await c.confirm();
    expect(c.phase, ImportPhase.imported);
    expect(await count('movements'), 8);
    expect(await photos(), before);
  });
  test('Fallo de escritura revierte lote, originales y movimientos; reintento correcto', () async {
    final before = await photos();
    selector.add(bankFixture());
    await select();
    await bind();
    await db.customStatement(
      "CREATE TRIGGER fail_openbank BEFORE INSERT ON movements WHEN (SELECT count(*) FROM movements)>0 BEGIN SELECT RAISE(ABORT,'synthetic-write-failure'); END",
    );
    await c.confirm();
    expect(c.phase, ImportPhase.error);
    expect(await count('movements'), 0);
    expect(await count('import_batches'), 0);
    expect(await count('import_row_originals'), 0);
    expect(await photos(), before);
    await db.customStatement('DROP TRIGGER fail_openbank');
    await c.refresh();
    await c.confirm();
    expect(c.phase, ImportPhase.imported);
    expect(await count('movements'), 4);
    expect(await photos(), before);
  });
}
