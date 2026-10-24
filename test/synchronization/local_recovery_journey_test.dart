import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/database_failure.dart';
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

class _PausedInstall extends NativeBackupPersistence {
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> move(
    String source,
    String target, {
    bool replace = false,
  }) async {
    if (p.basename(target) == 'journal-003.json') {
      entered.complete();
      await release.future;
    }
    await super.move(source, target, replace: replace);
  }
}

final class _RecoveryJourney {
  _RecoveryJourney(this.support)
    : store = LocalDatabaseStore(supportDirectory: () async => support);

  final Directory support;
  LocalDatabaseStore store;
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

  Future<LocalRestoreResult> restoreAndVerify(
    String backupId,
    Map<String, Object?> expected,
  ) async {
    final reader = createLocalSyncContrastReader(
      supportDirectory: () async => support,
    );
    final before = await reader.read();
    final result = await restorer().restore(backupId, confirmed: true);
    expect(result.status, LocalRestoreStatus.restored);
    expect(result.previousBackupId, isNotNull);
    expect(result.maintenancePending, false);
    await verify(expected);
    await restart();
    await verify(expected);
    final after = await reader.read();
    expect(after.required, true);
    expect(after.restoreEpoch, isNot(before.restoreEpoch));
    return result;
  }

  Future<void> seed() async {
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
  }

  Future<void>? _running;
  Future<void>? _disposing;

  Future<void> run(Future<void> Function() body) =>
      _running = Future<void>.sync(body);

  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    // Un timeout del observador no cancela I/O. Drenar el cuerpo antes de
    // cerrar SQLite o borrar su carpeta; el fallo ya lo recibe quien espera run.
    try {
      await _running;
    } catch (_) {
      // La limpieza también es obligatoria cuando falla una aserción.
    }
    await store.close();
    await support.delete(recursive: true);
  }
}

// Siete intercambios, reaperturas y retención con fsync nativo superan los
// 30 s en Windows. El plazo sigue siendo finito; las señales sincronizan I/O.
const _journeyTimeout = Timeout(Duration(minutes: 3));

void _journeyTest(
  String name,
  Future<void> Function(_RecoveryJourney) body, {
  Timeout timeout = _journeyTimeout,
}) {
  test(name, () async {
    final journey = _RecoveryJourney(
      await Directory.systemTemp.createTemp('recovery-ep001-'),
    );
    addTearDown(journey.dispose);
    await journey.run(() async {
      await journey.seed();
      await body(journey);
    });
  }, timeout: timeout);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'observador terminado: drena la restauración y aísla el siguiente fixture',
    () async {
      final owner = _RecoveryJourney(
        await Directory.systemTemp.createTemp('recovery-owner-'),
      );
      addTearDown(owner.dispose);
      final gate = _PausedInstall();
      final operation = owner.run(() async {
        await owner.seed();
        final result = await owner
            .restorer(persistence: gate)
            .restore(owner.first.backupId, confirmed: true);
        expect(result.status, LocalRestoreStatus.restored);
        await owner.restart();
        await owner.verify(owner.original);
      });
      try {
        await Future.any([
          gate.entered.future,
          operation.then((_) => fail('No se alcanzó la instalación pausada.')),
        ]);
        // Equivalente a que venza el plazo de quien observa el Future:
        // termina la espera, pero Dart no cancela el intercambio pendiente.
        final observerEnded = Completer<void>();
        final observation = Future.any([operation, observerEnded.future]);
        observerEnded.complete();
        await observation;

        var disposed = false;
        final cleanup = owner.dispose().then((_) => disposed = true);
        final next = _RecoveryJourney(
          await Directory.systemTemp.createTemp('recovery-next-'),
        );
        addTearDown(next.dispose);
        await next.run(() async {
          await next.seed();
          await next.verify(next.modified);
          await next.store.close();
        });
        expect(next.support.path, isNot(owner.support.path));
        expect(disposed, false);
        expect(await owner.support.exists(), true);
        await expectLater(
          owner.store.open(),
          throwsA(
            isA<DatabaseFailure>().having(
              (e) => e.code,
              'exclusión durante el intercambio',
              DatabaseFailureCode.restoring,
            ),
          ),
        );
        gate.release.complete();
        await operation;
        await cleanup;
        expect(disposed, true);
        expect(await owner.support.exists(), false);
        await next.run(() async {
          await next.restart();
          await next.verify(next.modified);
        });
        await next.dispose();
        expect(await next.support.exists(), false);
      } finally {
        if (!gate.release.isCompleted) gate.release.complete();
        await operation;
      }
    },
    timeout: _journeyTimeout,
  );

  _journeyTest(
    'EP-001: dos manuales, restauración y recuperación de la anterior tras reinicios',
    (journey) async {
      final second = await createLocalBackupCreator(
        store: journey.store,
        supportDirectory: () async => journey.support,
      ).createManual();
      await journey.restart();
      await journey.verify(journey.modified);
      final result = await journey.restoreAndVerify(
        journey.first.backupId,
        journey.original,
      );
      await journey.restoreAndVerify(
        result.previousBackupId!,
        journey.modified,
      );
      final automaticIds = <String>[];
      for (var i = 0; i < 4; i++) {
        final restored = await journey.restoreAndVerify(
          journey.first.backupId,
          journey.original,
        );
        automaticIds.add(restored.previousBackupId!);
      }
      final listing = await createLocalBackupCatalog(
        supportDirectory: () async => journey.support,
      ).read();
      expect(
        listing.entries
            .where((e) => e.origin == LocalBackupOrigin.preRestore)
            .map((e) => e.backupId),
        unorderedEquals(automaticIds.skip(1)),
      );
      expect(
        listing.entries
            .where((e) => e.origin == LocalBackupOrigin.manual)
            .map((e) => e.backupId),
        unorderedEquals([journey.first.backupId, second.backupId]),
      );
      // La segunda manual sigue restaurable después de la poda y los reinicios.
      await journey.restoreAndVerify(second.backupId, journey.modified);
    },
  );

  _journeyTest(
    'fallo de disco tras instalar: rollback íntegro y sin contraste nuevo',
    (journey) async {
      final result = await journey
          .restorer(persistence: _FullDisk())
          .restore(journey.first.backupId, confirmed: true);
      expect(result.status, LocalRestoreStatus.rolledBack);
      expect(result.previousBackupId, isNotNull);
      await journey.restart();
      await journey.verify(journey.modified);
      expect(
        (await createLocalSyncContrastReader(
          supportDirectory: () async => journey.support,
        ).read()).required,
        false,
      );
      expect(
        (await journey.restorer().restore(
          journey.first.backupId,
          confirmed: true,
        )).status,
        LocalRestoreStatus.restored,
      );
      await journey.restart();
      await journey.verify(journey.original);
    },
  );

  _journeyTest(
    'cuarta fallida conserva exceso; siguiente éxito retiene las tres más recientes',
    (journey) async {
      for (var i = 0; i < 3; i++) {
        expect(
          (await journey.restorer().restore(
            journey.first.backupId,
            confirmed: true,
          )).status,
          LocalRestoreStatus.restored,
        );
      }
      expect(
        (await journey
                .restorer(persistence: _FullDisk())
                .restore(journey.first.backupId, confirmed: true))
            .status,
        LocalRestoreStatus.rolledBack,
      );
      await journey.restart();
      await journey.verify(journey.original);
      final catalog = createLocalBackupCatalog(
        supportDirectory: () async => journey.support,
      );
      final excess =
          (await catalog.read()).entries
              .where((e) => e.origin == LocalBackupOrigin.preRestore)
              .toList()
            ..sort((a, b) => a.creationOrder.compareTo(b.creationOrder));
      expect(excess, hasLength(4));
      final result = await journey.restorer().restore(
        journey.first.backupId,
        confirmed: true,
      );
      expect(result.status, LocalRestoreStatus.restored);
      await journey.restart();
      await journey.verify(journey.original);
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
        journey.first.backupId,
      );
    },
  );

  for (final damage in ['truncated', 'future']) {
    _journeyTest(
      '$damage: rechaza sin perder activa ni manual y persiste al reiniciar',
      (journey) async {
        final image = File(
          p.join(
            journey.root(),
            journey.first.relativeDirectory,
            'autofinance.sqlite',
          ),
        );
        if (damage == 'truncated') {
          await image.writeAsBytes(
            (await image.readAsBytes()).take(512).toList(),
            flush: true,
          );
        } else {
          final db = sqlite3.open(image.path);
          db.execute('PRAGMA user_version=99');
          db.close();
          final manifest = File(p.join(p.dirname(image.path), 'manifest.json'));
          final metadata = decodeBackupEnvelope(await manifest.readAsBytes());
          metadata['schemaVersion'] = 99;
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
          final catalog = (await storage.loadSlots(journey.root())).latest!;
          final entry =
              (catalog['entries'] as List).single as Map<String, dynamic>;
          entry['descriptor'] = metadata;
          entry['manifestPayloadSha256'] = backupPayloadHash(metadata);
          await storage.commitCatalog(journey.root(), catalog);
        }
        final bytes = await image.readAsBytes();
        final result = await journey.restorer().restore(
          journey.first.backupId,
          confirmed: true,
        );
        expect(result.status, LocalRestoreStatus.rejected);
        expect(
          result.candidateIssue,
          damage == 'future'
              ? LocalRestoreCandidateIssue.futureSchema
              : LocalRestoreCandidateIssue.sizeMismatch,
        );
        await journey.restart();
        await journey.verify(journey.modified);
        expect(await image.readAsBytes(), bytes);
        expect(
          (await createLocalSyncContrastReader(
            supportDirectory: () async => journey.support,
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
    _journeyTest(
      'proceso terminado en $phase: recuperación real y segundo reinicio',
      (journey) async {
        await journey.store.close();
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
        // El pubspec declara las fuentes locales del kit. El proceso hijo
        // necesita el bundle completo, aunque esta prueba no abra pantallas.
        for (final source in ['lib', 'assets']) {
          await for (final file in Directory(
            source,
          ).list(recursive: true, followLinks: false)) {
            if (file is! File) continue;
            final destination = p.join(worker.path, file.path);
            await Directory(p.dirname(destination)).create(recursive: true);
            await file.copy(destination);
          }
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
            '--dart-define=CRASH_SUPPORT=${journey.support.path}',
            '--dart-define=CRASH_BACKUP=${journey.first.backupId}',
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
        await journey.restart();
        final completed = phase == 'journal-004.json';
        await journey.verify(completed ? journey.original : journey.modified);
        final signal = await createLocalSyncContrastReader(
          supportDirectory: () async => journey.support,
        ).read();
        expect(signal.required, completed);
        final listing = await createLocalBackupCatalog(
          supportDirectory: () async => journey.support,
        ).read();
        final previous = listing.entries.singleWhere(
          (e) => e.origin == LocalBackupOrigin.preRestore,
        );
        await journey.restart();
        await journey.verify(completed ? journey.original : journey.modified);
        // El bloqueo del proceso muerto se liberó y la anterior sigue restaurable.
        expect(
          (await journey.restorer().restore(
            previous.backupId,
            confirmed: true,
          )).status,
          LocalRestoreStatus.restored,
        );
        await journey.restart();
        await journey.verify(journey.modified);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
