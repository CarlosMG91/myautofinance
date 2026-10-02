import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_wealth_repository.dart';
import 'package:myautofinance/app/local_backup_factory.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/synchronization/data/backup_json.dart';
import 'package:myautofinance/features/synchronization/data/backup_storage.dart';
import 'package:myautofinance/features/synchronization/data/native_backup_persistence.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import '../support/recovery_reference.dart';

// La comparación incluye todas las tablas, IDs, revisión y trazabilidad.
Future<Map<String, Object?>> contents(LocalDatabase db) async {
  final tables = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT GLOB 'sqlite_*' ORDER BY name",
      )
      .get();
  return {
    for (final table in tables)
      table.read<String>('name'): [
        for (final row
            in await db
                .customSelect(
                  'SELECT * FROM "${table.read<String>('name')}" ORDER BY rowid',
                )
                .get())
          row.data,
      ],
  };
}

class _FullDisk extends NativeBackupPersistence {
  bool armed = true;
  @override
  Future<void> move(
    String source,
    String target, {
    bool replace = false,
  }) async {
    if (armed && p.basename(target) == 'journal-003.json') {
      armed = false;
      throw const FileSystemException(
        'synthetic disk full',
        '',
        OSError('synthetic', 28),
      );
    }
    await super.move(source, target, replace: replace);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  late LocalDatabaseStore store;
  late CreatedLocalBackup first;
  late Map<String, Object?> original, modified;
  String root() => p.join(support.path, 'sqlite');
  Future<void> restart() async {
    await store.close();
    store = LocalDatabaseStore(supportDirectory: () async => support);
    await store.open();
  }

  Future<void> verify(Map<String, Object?> expected) async {
    final db = await store.open();
    expect(await contents(db), expected);
    expect(
      (await db.customSelect('PRAGMA integrity_check').getSingle())
          .data
          .values
          .single,
      'ok',
    );
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  }

  LocalRestorer restorer({NativeBackupPersistence? persistence}) =>
      createLocalRestorer(
        store: store,
        supportDirectory: () async => support,
        persistence: persistence,
      );
  setUp(() async {
    support = await Directory.systemTemp.createTemp('recovery-ep001-');
    store = LocalDatabaseStore(supportDirectory: () async => support);
    final db = await store.open();
    final account = await seedRecoveryReference(db);
    original = await contents(db);
    final real = await SqliteMovementRepository(db).readYear(2026);
    expect(real.length, 10);
    expect(real.fold<int>(0, (s, r) => s + r.data.amountCents), 232965);
    expect(
      (await SqliteMovementRepository(
        db,
      ).readMonth(2026, 1)).fold<int>(0, (s, r) => s + r.data.amountCents),
      122975,
    );
    expect(
      (await db.customSelect('SELECT COUNT(*) AS n FROM budgets').getSingle())
          .read<int>('n'),
      48,
    );
    final photos = SqliteWealthRepository(db);
    final january = await photos.read(Month(2026, 1));
    expect(january.status, WealthSnapshotStatus.complete);
    final liquid = january.values
        .where((v) => v.account.liquidity == Liquidity.liquid)
        .fold<int>(0, (s, v) => s + v.amountCents);
    expect(liquid, 900000);
    expect(liquid / (3600000 / 12), 3);
    expect(
      (await photos.read(Month(2026, 2))).status,
      WealthSnapshotStatus.absent,
    );
    expect(
      (await db
              .customSelect('SELECT SUM(amount_cents) AS n FROM budgets')
              .getSingle())
          .read<int>('n'),
      1320000,
    );
    first = await createLocalBackupCreator(
      store: store,
      supportDirectory: () async => support,
    ).createManual();
    // Simula un contraste previo resuelto; el fallo no debe inventar otro.
    final storage = BackupStorage(NativeBackupPersistence(), DateTime.now);
    final catalog = (await storage.loadSlots(root())).latest!;
    catalog['syncContrastRequired'] = false;
    await storage.commitCatalog(root(), catalog);
    await SqliteMovementRepository(db).create(
      MovementInput(
        accountId: account,
        valueDate: ValueDate(2026, 1, 31),
        concept: 'Modificación sintética posterior',
        amountCents: -12345,
      ),
    );
    modified = await contents(db);
  });
  tearDown(() async {
    await store.close();
    await support.delete(recursive: true);
  });

  test('EP-001: dos manuales, restauración y recuperación de la anterior tras reinicios', () async {
    final second = await createLocalBackupCreator(
      store: store,
      supportDirectory: () async => support,
    ).createManual();
    await restart();
    await verify(modified);
    final result = await restorer().restore(first.backupId, confirmed: true);
    expect(result.status, LocalRestoreStatus.restored);
    await restart();
    await verify(original);
    final signal = await createLocalSyncContrastReader(
      supportDirectory: () async => support,
    ).read();
    expect(signal.required, true);
    expect(
      (await restorer().restore(
        result.previousBackupId!,
        confirmed: true,
      )).status,
      LocalRestoreStatus.restored,
    );
    await restart();
    await verify(modified);
    expect(
      (await createLocalSyncContrastReader(
        supportDirectory: () async => support,
      ).read()).restoreEpoch,
      isNot(signal.restoreEpoch),
    );
    for (var i = 0; i < 4; i++) {
      expect(
        (await restorer().restore(first.backupId, confirmed: true)).status,
        LocalRestoreStatus.restored,
      );
    }
    await restart();
    await verify(original);
    final listing = await createLocalBackupCatalog(
      supportDirectory: () async => support,
    ).read();
    expect(
      listing.entries.where((e) => e.origin == LocalBackupOrigin.preRestore),
      hasLength(3),
    );
    expect(
      listing.entries
          .where((e) => e.origin == LocalBackupOrigin.manual)
          .map((e) => e.backupId),
      unorderedEquals([first.backupId, second.backupId]),
    );
    // La segunda manual sigue restaurable después de la poda y los reinicios.
    expect(
      (await restorer().restore(second.backupId, confirmed: true)).status,
      LocalRestoreStatus.restored,
    );
    await restart();
    await verify(modified);
  });

  test(
    'fallo de disco tras instalar: rollback íntegro y sin contraste nuevo',
    () async {
      final result = await restorer(persistence: _FullDisk())
          .restore(first.backupId, confirmed: true);
      expect(result.status, LocalRestoreStatus.rolledBack);
      expect(result.previousBackupId, isNotNull);
      await restart();
      await verify(modified);
      expect(
        (await createLocalSyncContrastReader(
          supportDirectory: () async => support,
        ).read()).required,
        false,
      );
      expect(
        (await restorer().restore(first.backupId, confirmed: true)).status,
        LocalRestoreStatus.restored,
      );
      await restart();
      await verify(original);
    },
  );

  test('cuarta fallida conserva exceso; siguiente éxito retiene las tres más recientes', () async {
    for (var i = 0; i < 3; i++) {
      expect(
        (await restorer().restore(first.backupId, confirmed: true)).status,
        LocalRestoreStatus.restored,
      );
    }
    expect(
      (await restorer(
        persistence: _FullDisk(),
      ).restore(first.backupId, confirmed: true)).status,
      LocalRestoreStatus.rolledBack,
    );
    await restart();
    await verify(original);
    final catalog = createLocalBackupCatalog(
      supportDirectory: () async => support,
    );
    final excess =
        (await catalog.read()).entries
            .where((e) => e.origin == LocalBackupOrigin.preRestore)
            .toList()
          ..sort((a, b) => a.creationOrder.compareTo(b.creationOrder));
    expect(excess, hasLength(4));
    final result = await restorer().restore(first.backupId, confirmed: true);
    expect(result.status, LocalRestoreStatus.restored);
    await restart();
    await verify(original);
    final entries = (await catalog.read()).entries;
    expect(
      entries
          .where((e) => e.origin == LocalBackupOrigin.preRestore)
          .map((e) => e.backupId),
      unorderedEquals([
        excess[2].backupId,
        excess[3].backupId,
        result.previousBackupId,
      ]),
    );
    expect(
      entries
          .where((e) => e.origin == LocalBackupOrigin.manual)
          .single
          .backupId,
      first.backupId,
    );
  });

  for (final damage in ['truncated', 'future']) {
    test(
      '$damage: rechaza sin perder activa ni manual y persiste al reiniciar',
      () async {
        final image = File(
          p.join(root(), first.relativeDirectory, 'autofinance.sqlite'),
        );
        if (damage == 'truncated') {
          await image.writeAsBytes(
            (await image.readAsBytes()).take(512).toList(),
            flush: true,
          );
        } else {
          final db = sqlite3.open(image.path);
          db.execute('PRAGMA user_version=7');
          db.close();
          final manifest = File(p.join(p.dirname(image.path), 'manifest.json'));
          final metadata = decodeBackupEnvelope(await manifest.readAsBytes());
          metadata['schemaVersion'] = 7;
          metadata['databaseSha256'] = sha256
              .convert(await image.readAsBytes())
              .toString();
          metadata['sizeBytes'] = '${await image.length()}';
          await manifest.writeAsBytes(
            encodeBackupEnvelope(metadata),
            flush: true,
          );
          final storage = BackupStorage(
            NativeBackupPersistence(),
            DateTime.now,
          );
          final catalog = (await storage.loadSlots(root())).latest!;
          final entry =
              (catalog['entries'] as List).single as Map<String, dynamic>;
          entry['descriptor'] = metadata;
          entry['manifestPayloadSha256'] = backupPayloadHash(metadata);
          await storage.commitCatalog(root(), catalog);
        }
        final bytes = await image.readAsBytes();
        final result = await restorer().restore(
          first.backupId,
          confirmed: true,
        );
        expect(result.status, LocalRestoreStatus.rejected);
        expect(
          result.candidateIssue,
          damage == 'future'
              ? LocalRestoreCandidateIssue.futureSchema
              : LocalRestoreCandidateIssue.sizeMismatch,
        );
        await restart();
        await verify(modified);
        expect(await image.readAsBytes(), bytes);
        expect(
          (await createLocalSyncContrastReader(
            supportDirectory: () async => support,
          ).read()).required,
          false,
        );
      },
    );
  }

  for (final phase in [
    'journal-002.json',
    'journal-003.json',
    'journal-004.json',
  ]) {
    test(
      'proceso terminado en $phase: recuperación real y segundo reinicio',
      () async {
        await store.close();
        final config = jsonDecode(
          await File('.dart_tool/package_config.json').readAsString(),
        ) as Map<String, dynamic>;
        final flutterRoot = Uri.parse(config['flutterRoot'] as String)
            .toFilePath();
        // Un build privado evita intentar borrar la DLL SQLite cargada por
        // el runner padre en Windows. No altera la configuración del SDK.
        final worker = await Directory.systemTemp.createTemp('restore-worker-');
        addTearDown(() async => worker.delete(recursive: true));
        for (final path in [
          'pubspec.yaml',
          'pubspec.lock',
          '.dart_tool/package_config.json',
          '.dart_tool/package_graph.json',
          'test/support/restore_crash_worker.dart',
        ]) {
          final destination = p.join(worker.path, path);
          await Directory(p.dirname(destination)).create(recursive: true);
          await File(path).copy(destination);
        }
        await for (final file in Directory(
          'lib',
        ).list(recursive: true, followLinks: false)) {
          if (file is! File) continue;
          final destination = p.join(worker.path, file.path);
          await Directory(p.dirname(destination)).create(recursive: true);
          await file.copy(destination);
        }
        final process = await Process.start(
          p.join(
            flutterRoot,
            'bin',
            Platform.isWindows ? 'flutter.bat' : 'flutter',
          ),
          [
            'test',
            '--no-pub',
            '--reporter=expanded',
            '--dart-define=CRASH_SUPPORT=${support.path}',
            '--dart-define=CRASH_BACKUP=${first.backupId}',
            '--dart-define=CRASH_PHASE=$phase',
            'test/support/restore_crash_worker.dart',
          ],
          runInShell: Platform.isWindows,
          workingDirectory: worker.path,
        );
        final output = process.stdout.transform(utf8.decoder).join();
        final errors = process.stderr.transform(utf8.decoder).join();
        try {
          expect(
            await process.exitCode.timeout(const Duration(seconds: 90)),
            isNot(0),
          );
          expect(
            await output,
            contains('durable-crash-point'),
            reason: await errors,
          );
        } finally {
          process.kill();
          await process.exitCode;
        }
        await restart();
        final completed = phase == 'journal-004.json';
        await verify(completed ? original : modified);
        final signal = await createLocalSyncContrastReader(
          supportDirectory: () async => support,
        ).read();
        expect(signal.required, completed);
        final listing = await createLocalBackupCatalog(
          supportDirectory: () async => support,
        ).read();
        final previous = listing.entries.singleWhere(
          (e) => e.origin == LocalBackupOrigin.preRestore,
        );
        await restart();
        await verify(completed ? original : modified);
        // El bloqueo del proceso muerto se liberó y la anterior sigue restaurable.
        expect(
          (await restorer().restore(previous.backupId, confirmed: true)).status,
          LocalRestoreStatus.restored,
        );
        await restart();
        await verify(modified);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
