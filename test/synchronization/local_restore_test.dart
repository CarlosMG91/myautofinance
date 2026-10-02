import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/database_failure.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_restore_image_policy.dart';
import 'package:myautofinance/app/local_backup_factory.dart';
import 'package:myautofinance/features/synchronization/data/backup_json.dart';
import 'package:myautofinance/features/synchronization/data/backup_storage.dart';
import 'package:myautofinance/features/synchronization/data/local_backup_service.dart';
import 'package:myautofinance/features/synchronization/data/local_restore_candidate_service.dart';
import 'package:myautofinance/features/synchronization/data/local_restore_service.dart';
import 'package:myautofinance/features/synchronization/data/native_backup_persistence.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';
import 'package:path/path.dart' as p;

class _Faults extends NativeBackupPersistence {
  Future<void> Function(String, String)? before;
  Future<void> Function(String, String)? after;
  @override
  Future<void> move(
    String source,
    String target, {
    bool replace = false,
  }) async {
    await before?.call(source, target);
    await super.move(source, target, replace: replace);
    await after?.call(source, target);
  }
}

class _Active implements LocalRestoreActiveDatabase {
  _Active(this.store);
  final LocalDatabaseStore store;
  int reopenCalls = 0;
  bool failFirstReopen = false;
  bool failClose = false;
  bool failBackup = false;
  @override
  Future<T> exclusivelyForRestore<T>(Future<T> Function() action) =>
      store.exclusivelyForRestore(action);
  @override
  Future<bool> canOpenExisting() => store.canOpenExisting();
  @override
  Future<LocalBackup> createConsistentBackup() {
    if (failBackup) throw const FileSystemException('synthetic backup failure');
    return store.createConsistentBackup();
  }

  @override
  Future<void> close() async {
    if (failClose) {
      failClose = false;
      throw const FileSystemException('synthetic close failure');
    }
    await store.close();
  }

  @override
  Future<LocalBackupImage> reopenAndValidate() async {
    final image = await store.reopenAndValidate();
    if (++reopenCalls == 1 && failFirstReopen) {
      throw const FileSystemException('synthetic validation failure');
    }
    return image;
  }

  @override
  void requireRecovery() => store.requireRecovery();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  late LocalDatabaseStore store;
  late _Active active;
  late _Faults persistence;
  late CreatedLocalBackup selected;
  late LocalRestorer service;
  String root() => p.join(support.path, 'sqlite');
  String activePath() => p.join(root(), 'autofinance.sqlite');
  BackupStorage storage() => BackupStorage(persistence, DateTime.now);

  Future<Map<String, String>> files() async => {
    await for (final file in support.list(recursive: true, followLinks: false))
      if (file is File)
        p.relative(file.path, from: support.path): sha256
            .convert(await file.readAsBytes())
            .toString(),
  };

  setUp(() async {
    support = await Directory.systemTemp.createTemp(
      'autofinance-restore-test-',
    );
    store = LocalDatabaseStore(supportDirectory: () async => support);
    active = _Active(store);
    persistence = _Faults();
    final db = await store.open();
    // Fixture sintético por SQL técnico: revisión inicial conocida.
    await db.customStatement(
      "INSERT INTO categories(id,name,is_income,created_at,updated_at) VALUES('11111111-1111-4111-8111-111111111111','Categoría de la copia',0,'2026-10-02T12:00:00.000Z','2026-10-02T12:00:00.000Z')",
    );
    selected = await createLocalBackupCreator(
      store: store,
      supportDirectory: () async => support,
    ).createManual();
    final baseline = (await storage().loadSlots(root())).latest!;
    baseline['syncContrastRequired'] = false;
    await storage().commitCatalog(root(), baseline);
    await db.writeTransaction(() async {
      await db.customStatement(
        "UPDATE categories SET name='Categoría posterior'",
      );
      await db.customStatement('UPDATE database_state SET revision=41');
    });
    service = LocalRestoreService(
      active: active,
      creator: LocalBackupService(
        source: active,
        validator: const SqliteLocalBackupValidator(),
        supportDirectory: () async => support,
        persistence: persistence,
      ),
      preparer: LocalRestoreCandidateService(
        policy: const SqliteRestoreImagePolicy(),
        supportDirectory: () async => support,
        persistence: persistence,
      ),
      catalog: createLocalBackupCatalog(
        supportDirectory: () async => support,
        persistence: persistence,
      ),
      supportDirectory: () async => support,
      persistence: persistence,
    );
  });
  tearDown(() async {
    await store.close();
    await support.delete(recursive: true);
  });

  test('cancelar no modifica ningún archivo y no abre ni captura', () async {
    await store.close();
    final before = await files();
    final result = await service.restore(
      'incluso-id-inválido',
      confirmed: false,
    );
    expect(result.status, LocalRestoreStatus.cancelled);
    expect(await files(), before);
    expect(active.reopenCalls, 0);
  });

  test(
    'éxito reabre datos esperados, conserva anterior y cambia epoch',
    () async {
      final epoch = (await storage().loadSlots(root()))
          .latest!['localRestoreEpoch'];
      final oldDb = await store.open();
      final result = await service.restore(selected.backupId, confirmed: true);
      expect(result.status, LocalRestoreStatus.restored);
      expect(result.previousBackupId, isNotNull);
      expect((await (await store.open()).readState()).revision, 0);
      expect(
        await (await store.open())
            .customSelect('SELECT count(*) AS n FROM categories')
            .getSingle()
            .then((r) => r.read<int>('n')),
        1,
      );
      expect(
        (await (await store.open())
                .customSelect('SELECT name FROM categories')
                .getSingle())
            .read<String>('name'),
        'Categoría de la copia',
      );
      await expectLater(
        oldDb.writeTransaction(() async {}),
        throwsA(isA<DatabaseFailure>()),
      );
      final value = (await storage().loadSlots(root())).latest!;
      expect(value['localRestoreEpoch'], isNot(epoch));
      expect(value['syncContrastRequired'], true);
      final original = File(
        p.join(
          root(),
          'local-backups',
          'backups',
          result.previousBackupId!,
          'autofinance.sqlite',
        ),
      );
      expect(
        (await const SqliteLocalBackupValidator().validate(original.path))
            .state
            .revision,
        42,
      );
      final listing = await createLocalBackupCatalog(
        supportDirectory: () async => support,
      ).read();
      expect(
        listing.incidents.where(
          (i) => i.issue == LocalBackupCatalogIssue.unresolvedRestore,
        ),
        isEmpty,
      );
    },
  );

  test(
    'activa dañada: aísla exactamente main y sidecars y restaura catálogo',
    () async {
      await store.close();
      final bytes = <String, List<int>>{
        '': [1, 2, 3, 4],
        '-wal': [7, 8],
        '-shm': [9],
        '-journal': [10, 11],
      };
      for (final entry in bytes.entries) {
        await File('${activePath()}${entry.key}').writeAsBytes(entry.value);
      }
      final result = await service.restore(selected.backupId, confirmed: true);
      expect(result.status, LocalRestoreStatus.restored);
      expect(result.previousBackupId, isNull);
      expect((await (await store.open()).readState()).revision, 0);
      final originals =
          await Directory(p.join(root(), 'local-backups', 'diagnostics'))
              .list(recursive: true)
              .where(
                (e) => e is File && p.basename(p.dirname(e.path)) == 'previous',
              )
              .toList();
      expect(originals.length, 4);
      for (final original in originals) {
        expect(
          await File(original.path).readAsBytes(),
          bytes[p
              .basename(original.path)
              .substring('autofinance.sqlite'.length)],
        );
      }
    },
  );

  for (final failure in [
    'isolate-before',
    'isolate-after',
    'install-before',
    'install-after',
    'installed-journal',
    'validated-journal',
    'catalog-before',
    'catalog-after',
    'completed-journal',
  ]) {
    test('$failure restablece la activa y epoch y conserva respaldo', () async {
      final epoch = (await storage().loadSlots(root()))
          .latest!['localRestoreEpoch'];
      var fired = false;
      Future<void> inject(String source, String target, bool after) async {
        if (fired) return;
        final name = p.basename(target);
        final hit = switch (failure) {
          'isolate-before' =>
            !after &&
                target.contains('${p.separator}previous${p.separator}') &&
                name == 'autofinance.sqlite',
          'isolate-after' =>
            after &&
                target.contains('${p.separator}previous${p.separator}') &&
                name == 'autofinance.sqlite',
          'install-before' => !after && target == activePath(),
          'install-after' => after && target == activePath(),
          'installed-journal' => !after && name == 'journal-003.json',
          'validated-journal' => !after && name == 'journal-004.json',
          'catalog-before' || 'catalog-after' =>
            after == (failure == 'catalog-after') &&
                name.startsWith('catalog-') &&
                name.endsWith('.json') &&
                (decodeBackupEnvelope(
                      await File(after ? target : source).readAsBytes(),
                    )['localRestoreEpoch'] !=
                    epoch),
          'completed-journal' => !after && name == 'journal-005.json',
          _ => false,
        };
        if (hit) {
          fired = true;
          throw const FileSystemException('synthetic fault');
        }
      }

      persistence.before = (s, t) => inject(s, t, false);
      persistence.after = (s, t) => inject(s, t, true);
      final result = await service.restore(selected.backupId, confirmed: true);
      expect(fired, true);
      expect(result.status, LocalRestoreStatus.rolledBack);
      expect(result.previousBackupId, isNotNull);
      expect((await (await store.open()).readState()).revision, 42);
      expect(
        (await storage().loadSlots(root())).latest!['localRestoreEpoch'],
        epoch,
      );
      expect(
        (await storage().loadSlots(root())).latest!['syncContrastRequired'],
        false,
      );
      final entries =
          (await storage().loadSlots(root())).latest!['entries'] as List;
      expect(entries.length, 2);
    });
  }

  test(
    'fallo de reapertura/validación revierte antes de anunciar éxito',
    () async {
      active.failFirstReopen = true;
      final result = await service.restore(selected.backupId, confirmed: true);
      expect(result.status, LocalRestoreStatus.rolledBack);
      expect(active.reopenCalls, 2);
      expect((await (await store.open()).readState()).revision, 42);
    },
  );

  for (final failure in ['close', 'backup']) {
    test('fallo de $failure no sustituye activa ni poda', () async {
      active.failClose = failure == 'close';
      active.failBackup = failure == 'backup';
      final result = await service.restore(selected.backupId, confirmed: true);
      expect(result.status, LocalRestoreStatus.rolledBack);
      expect((await (await store.open()).readState()).revision, 42);
      expect(
        await File(
          p.join(root(), selected.relativeDirectory, 'autofinance.sqlite'),
        ).exists(),
        true,
      );
    });
  }

  test('rechaza candidata alterada sin tocar activa', () async {
    final original = File(
      p.join(root(), selected.relativeDirectory, 'autofinance.sqlite'),
    );
    await original.writeAsBytes([1, 2, 3]);
    final result = await service.restore(selected.backupId, confirmed: true);
    expect(result.status, LocalRestoreStatus.rejected);
    expect(result.candidateIssue, LocalRestoreCandidateIssue.sizeMismatch);
    expect((await (await store.open()).readState()).revision, 42);
  });

  test(
    'drena transacción admitida y bloquea nuevas escrituras y apertura',
    () async {
      final db = await store.open();
      final entered = Completer<void>();
      final finish = Completer<void>();
      final transaction = db.writeTransaction(() async {
        entered.complete();
        await finish.future;
        await db.customStatement('UPDATE database_state SET revision=43');
      });
      await entered.future;
      final restoring = service.restore(selected.backupId, confirmed: true);
      // Esperar a la adquisición real del bloqueo, sin temporización dependiente del host.
      for (var i = 0; i < 1000; i++) {
        try {
          await store.open();
        } on DatabaseFailure catch (e) {
          if (e.code == DatabaseFailureCode.restoring) break;
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await expectLater(store.open(), throwsA(isA<DatabaseFailure>()));
      await expectLater(
        db.writeTransaction(() async {}),
        throwsA(isA<DatabaseFailure>()),
      );
      finish.complete();
      await transaction;
      final result = await restoring;
      expect(result.status, LocalRestoreStatus.restored);
      final previous = p.join(
        root(),
        'local-backups',
        'backups',
        result.previousBackupId!,
        'autofinance.sqlite',
      );
      expect(
        (await const SqliteLocalBackupValidator().validate(previous))
            .state
            .revision,
        43,
      );
    },
  );

  test('rollback imposible conserva originales y bloquea acceso', () async {
    persistence.before = (source, target) async {
      if (target == activePath()) {
        throw const FileSystemException('persistent synthetic failure');
      }
    };
    final result = await service.restore(selected.backupId, confirmed: true);
    expect(result.status, LocalRestoreStatus.recoveryRequired);
    await expectLater(store.open(), throwsA(isA<DatabaseFailure>()));
    expect(
      await File(
        p.join(
          root(),
          'local-backups',
          'backups',
          result.previousBackupId!,
          'autofinance.sqlite',
        ),
      ).exists(),
      true,
    );
    expect(
      await Directory(p.join(root(), 'local-backups', 'restore'))
          .list(recursive: true)
          .any(
            (e) =>
                p.basename(e.path) == 'autofinance.sqlite' &&
                p.basename(p.dirname(e.path)) == 'previous',
          ),
      true,
    );
    final restarted = LocalDatabaseStore(supportDirectory: () async => support);
    await expectLater(restarted.open(), throwsA(isA<DatabaseFailure>()));
    expect(await File(activePath()).exists(), false);
    await restarted.close();
  });

  test('bloqueo nativo compartido rechaza una segunda operación', () async {
    await persistence.exclusively(
      p.join(root(), '.local-backups.lock'),
      () async {
        final result = await service.restore(
          selected.backupId,
          confirmed: true,
        );
        expect(result.status, LocalRestoreStatus.rejected);
        expect(
          result.candidateIssue,
          LocalRestoreCandidateIssue.operationInProgress,
        );
      },
    );
    expect((await (await store.open()).readState()).revision, 42);
  });

  test('no restaurar dentro de una unidad de trabajo', () async {
    final db = await store.open();
    await db.writeTransaction(() async {
      final result = await service.restore(selected.backupId, confirmed: true);
      expect(result.status, LocalRestoreStatus.rejected);
    });
    expect((await db.readState()).revision, 42);
  });

  test('bytes instalados alterados se detectan antes de abrir', () async {
    var altered = false;
    persistence.after = (source, target) async {
      if (target == activePath() && !altered) {
        altered = true;
        await File(target).writeAsBytes([1, 2, 3]);
      }
    };
    final result = await service.restore(selected.backupId, confirmed: true);
    expect(altered, true);
    expect(result.status, LocalRestoreStatus.rolledBack);
    expect(active.reopenCalls, 1); // Solo reapertura de la anterior.
    expect((await (await store.open()).readState()).revision, 42);
  });

  test('candidata preparada alterada aborta sin intercambio', () async {
    persistence.before = (source, target) async {
      if (p.basename(target) == 'journal-000.json') {
        await File(p.join(p.dirname(target), 'autofinance.sqlite'))
            .writeAsBytes([1]);
      }
    };
    final result = await service.restore(selected.backupId, confirmed: true);
    expect(result.status, LocalRestoreStatus.rolledBack);
    expect((await (await store.open()).readState()).revision, 42);
  });

  test(
    'fallo de limpieza posterior conserva éxito validado con aviso',
    () async {
      persistence.before = (source, target) async {
        if (p.basename(p.dirname(target)) == 'diagnostics') {
          throw const FileSystemException('synthetic cleanup failure');
        }
      };
      final result = await service.restore(selected.backupId, confirmed: true);
      expect(result.status, LocalRestoreStatus.restored);
      expect(result.maintenancePending, true);
      expect((await (await store.open()).readState()).revision, 0);
      // No iniciar una nueva restauración mientras el diario no esté archivado.
      final second = await service.restore(selected.backupId, confirmed: true);
      expect(second.status, LocalRestoreStatus.recoveryRequired);
    },
  );

  test(
    'cuatro éxitos retienen tres automáticas y todas las manuales',
    () async {
      for (var i = 0; i < 4; i++) {
        expect(
          (await service.restore(selected.backupId, confirmed: true)).status,
          LocalRestoreStatus.restored,
        );
      }
      final list = await createLocalBackupCatalog(
        supportDirectory: () async => support,
      ).read();
      expect(
        list.entries
            .where((e) => e.origin == LocalBackupOrigin.preRestore)
            .length,
        3,
      );
      expect(
        list.entries
            .where((e) => e.origin == LocalBackupOrigin.manual)
            .single
            .backupId,
        selected.backupId,
      );
    },
  );
}
