import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/local_backup_factory.dart';
import 'package:myautofinance/features/synchronization/data/backup_json.dart';
import 'package:myautofinance/features/synchronization/data/local_backup_catalog_service.dart';
import 'package:myautofinance/features/synchronization/data/local_backup_service.dart';
import 'package:myautofinance/features/synchronization/data/native_backup_persistence.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';
import 'package:path/path.dart' as p;

String operation(int n) =>
    '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

class _Persistence extends NativeBackupPersistence {
  bool failDelete = false;
  bool failWrite = false;
  bool failFlush = false;
  int? failAfterDelete;
  int deletes = 0;
  int? failCatalogCommit;
  int commits = 0;
  @override
  Future<void> deleteFile(String path) async {
    if (failDelete || failAfterDelete == deletes) {
      throw const FileSystemException('synthetic delete');
    }
    await super.deleteFile(path);
    deletes++;
  }

  @override
  Future<void> flushFile(String path) async {
    if (failFlush) throw const FileSystemException('synthetic no space');
    await super.flushFile(path);
  }

  @override
  Future<void> move(
    String source,
    String target, {
    bool replace = false,
  }) async {
    if (replace && p.basename(target).startsWith('catalog-')) {
      commits++;
      if (commits == failCatalogCommit) {
        throw const FileSystemException('synthetic interrupted commit');
      }
    }
    if (failWrite && p.basename(p.dirname(target)) == 'tombstones') {
      throw const FileSystemException('synthetic no space');
    }
    await super.move(source, target, replace: replace);
  }
}

class _Validator implements LocalBackupImageValidator {
  int calls = 0;
  Future<void> Function(String)? before;
  @override
  Future<LocalBackupImage> validate(String path) async {
    calls++;
    await before?.call(path);
    return const SqliteLocalBackupValidator().validate(path);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  late LocalDatabaseStore store;
  late _Persistence persistence;
  late _Validator validator;
  late DateTime clock;
  String root() => p.join(support.path, 'sqlite');
  String base() => p.join(root(), 'local-backups');
  File slot(String name) => File(p.join(base(), 'catalog-$name.json'));
  Directory artifact(String id) => Directory(p.join(base(), 'backups', id));
  File image(String id) =>
      File(p.join(artifact(id).path, 'autofinance.sqlite'));
  File tombstone(String id) => File(p.join(base(), 'tombstones', '$id.json'));
  LocalBackupCatalogService manager() => LocalBackupCatalogService(
    supportDirectory: () async => support,
    validator: validator,
    persistence: persistence,
    clock: () => clock,
  );
  LocalBackupService creator() => LocalBackupService(
    source: store,
    validator: const SqliteLocalBackupValidator(),
    supportDirectory: () async => support,
    clock: () => clock,
  );
  Future<CreatedLocalBackup> automatic(int n) =>
      creator().createPreRestore(operation(n));
  Future<List<CreatedLocalBackup>> automatics(int n) async => [
    for (var i = 1; i <= n; i++) await automatic(i),
  ];
  Future<Map<String, dynamic>> catalog() async {
    final values = <Map<String, dynamic>>[];
    for (final name in ['a', 'b']) {
      if (await slot(name).exists()) {
        values.add(decodeBackupEnvelope(await slot(name).readAsBytes()));
      }
    }
    values.sort(
      (a, b) =>
          backupCounter(b['generation'])
              .compareTo(backupCounter(a['generation'])),
    );
    return values.first;
  }

  Future<void> writeSlots(Map<String, dynamic> value) async {
    for (final name in ['a', 'b']) {
      await slot(name).writeAsBytes(encodeBackupEnvelope(value), flush: true);
    }
  }

  Future<void> corrupt(String id) async {
    final bytes = await image(id).readAsBytes();
    bytes[100] ^= 1;
    await image(id).writeAsBytes(bytes, flush: true);
  }

  Future<LocalBackupMaintenanceResult> confirm(
    int n, {
    Set<String> protected = const {},
  }) => manager().maintainAfterRestore(
    restoreOperationId: operation(n),
    outcome: LocalRestoreRetentionOutcome.confirmed,
    protectedBackupIds: protected,
  );
  Future<void> checkIds(Iterable<String> ids) async {
    expect(
      (await manager().read()).entries.map((e) => e.backupId),
      unorderedEquals(ids),
    );
  }

  setUp(() async {
    support = await Directory.systemTemp.createTemp(
      'backup-catalog-synthetic-',
    );
    store = LocalDatabaseStore(supportDirectory: () async => support);
    persistence = _Persistence();
    validator = _Validator();
    clock = DateTime.utc(2026, 10, 2, 12);
  });
  tearDown(() async {
    await store.close();
    expect(p.isWithin(Directory.systemTemp.path, support.path), true);
    await support.delete(recursive: true);
  });

  test('raíz nueva: catálogo vacío sin crear ni abrir SQLite', () async {
    final listing = await manager().read();
    expect(listing.status, LocalBackupCatalogStatus.empty);
    expect(listing.entries, isEmpty);
    expect(listing.incidents, isEmpty);
    expect(await File(p.join(root(), 'autofinance.sqlite')).exists(), false);
    expect(validator.calls, 0);
  });

  test('listado independiente de activa corrupta, orden, fecha, origen, tamaño y validación histórica', () async {
    final manual = await creator().createManual();
    clock = clock.add(const Duration(days: 1));
    final auto = await automatic(1);
    await store.close();
    final active = File(p.join(root(), 'autofinance.sqlite'));
    await active.writeAsString('activa ilegible');
    final activeBytes = await active.readAsBytes();
    final listing = await manager().read();
    expect(listing.status, LocalBackupCatalogStatus.ready);
    expect(listing.entries.map((e) => e.backupId), [
      auto.backupId,
      manual.backupId,
    ]);
    final entry = listing.entries.first;
    expect(entry.createdAtUtc, clock);
    expect(entry.origin, LocalBackupOrigin.preRestore);
    expect(entry.sizeBytes, await image(auto.backupId).length());
    expect(entry.validation, LocalBackupValidationState.valid);
    expect(entry.checkedAtUtc, clock);
    expect(validator.calls, 0);
    expect(await active.readAsBytes(), activeBytes);
  });

  test(
    'cuarta confirmación poda solo A1; manuales de igual hash permanecen',
    () async {
      final m1 = await creator().createManual();
      final m2 = await creator().createManual();
      final autos = await automatics(4);
      final bytes = await image(m1.backupId).readAsBytes();
      final result = await confirm(4);
      expect(result.deletedBackupIds, [autos.first.backupId]);
      expect(result.incidents, isEmpty);
      await checkIds([
        m1.backupId,
        m2.backupId,
        ...autos.skip(1).map((e) => e.backupId),
      ]);
      expect(await image(m1.backupId).readAsBytes(), bytes);
      final deletion = decodeBackupEnvelope(
        await tombstone(autos.first.backupId).readAsBytes(),
      );
      expect(deletion['reason'], 'retention');
      expect(deletion['restoreOperationId'], operation(4));
      expect(await artifact(autos.first.backupId).exists(), false);
    },
  );

  for (final outcome in [
    LocalRestoreRetentionOutcome.failed,
    LocalRestoreRetentionOutcome.cancelled,
    LocalRestoreRetentionOutcome.pending,
  ]) {
    test('$outcome nunca poda', () async {
      final autos = await automatics(4);
      final result = await manager().maintainAfterRestore(
        restoreOperationId: operation(4),
        outcome: outcome,
      );
      expect(result.deletedBackupIds, isEmpty);
      expect(persistence.deletes, 0);
      await checkIds(autos.map((e) => e.backupId));
      expect(await Directory(p.join(base(), 'tombstones')).exists(), false);
    });
  }

  test(
    'siguiente éxito poda exceso acumulado más antiguo de uno en uno',
    () async {
      final autos = await automatics(6);
      final result = await confirm(6);
      expect(result.deletedBackupIds, autos.take(3).map((e) => e.backupId));
      await checkIds(autos.skip(3).map((e) => e.backupId));
    },
  );

  test(
    'reloj atrasado: listado por fecha; poda por contador entero exacto',
    () async {
      final first = await automatic(1);
      clock = clock.subtract(const Duration(days: 1));
      final rest = [for (var i = 2; i <= 4; i++) await automatic(i)];
      expect((await manager().read()).entries.first.backupId, first.backupId);
      expect((await confirm(4)).deletedBackupIds, [first.backupId]);
      await checkIds(rest.map((e) => e.backupId));
    },
  );

  test('desempate por orden 10 > 9 y no por cadenas', () async {
    final autos = await automatics(10);
    expect(
      (await manager().read()).entries.take(2).map((e) => e.creationOrder),
      [10, 9],
    );
    expect(
      (await confirm(10)).deletedBackupIds,
      autos.take(7).map((e) => e.backupId),
    );
  });

  test(
    'única automática válida y dañadas: no borrar ni contar dañadas',
    () async {
      final autos = await automatics(4);
      for (final e in autos.skip(1)) {
        await corrupt(e.backupId);
      }
      final result = await confirm(4);
      expect(result.deletedBackupIds, isEmpty);
      expect(persistence.deletes, 0);
      expect(
        result.incidents.any(
          (i) => i.issue == LocalBackupCatalogIssue.insufficientValidBackups,
        ),
        true,
      );
      await checkIds(autos.map((e) => e.backupId));
    },
  );

  test('revalida supervivientes antes de cada baja; daño durante validación detiene poda', () async {
    final autos = await automatics(4);
    var visits = 0;
    validator.before = (path) async {
      if (p.basename(p.dirname(path)) == autos.last.backupId && ++visits == 2) {
        await corrupt(autos.last.backupId);
      }
    };
    final result = await confirm(4);
    expect(result.deletedBackupIds, isEmpty);
    expect(persistence.deletes, 0);
    expect(
      result.incidents.any(
        (i) => i.issue == LocalBackupCatalogIssue.insufficientValidBackups,
      ),
      true,
    );
  });

  test('copia en uso y diario no resuelto están protegidos', () async {
    final autos = await automatics(4);
    expect(
      (await confirm(4, protected: {autos.first.backupId})).deletedBackupIds,
      isEmpty,
    );
    final work = Directory(p.join(base(), 'restore', operation(99)));
    await work.create(recursive: true);
    final result = await confirm(4);
    expect(result.deletedBackupIds, isEmpty);
    expect(
      result.incidents.any(
        (i) => i.issue == LocalBackupCatalogIssue.unresolvedRestore,
      ),
      true,
    );
  });

  test('baja expresa: bloquea última válida y permite manual con superviviente verificada', () async {
    final m1 = await creator().createManual();
    final blocked = await manager().deleteExplicitly(m1.backupId);
    expect(blocked.deletedBackupIds, isEmpty);
    expect(
      blocked.incidents.single.issue,
      LocalBackupCatalogIssue.insufficientValidBackups,
    );
    final m2 = await creator().createManual();
    expect((await manager().deleteExplicitly(m1.backupId)).deletedBackupIds, [
      m1.backupId,
    ]);
    await checkIds([m2.backupId]);
    final deletion = decodeBackupEnvelope(
      await tombstone(m1.backupId).readAsBytes(),
    );
    expect(deletion['reason'], 'explicitUser');
    expect(deletion['restoreOperationId'], null);
  });

  test('baja expresa de copia en uso no escribe baja', () async {
    final m = await creator().createManual();
    await creator().createManual();
    final result = await manager().deleteExplicitly(
      m.backupId,
      protectedBackupIds: {m.backupId},
    );
    expect(result.deletedBackupIds, isEmpty);
    expect(await tombstone(m.backupId).exists(), false);
  });

  test('fallo de borrado conserva tres utilizables y deja baja reintentable al reiniciar', () async {
    final autos = await automatics(4);
    persistence.failDelete = true;
    final result = await confirm(4);
    expect(result.deletedBackupIds, isEmpty);
    expect(
      result.incidents.any(
        (i) => i.issue == LocalBackupCatalogIssue.deletionPending,
      ),
      true,
    );
    final listing = await manager().read();
    expect(
      listing.entries
          .singleWhere((e) => e.backupId == autos.first.backupId)
          .availability,
      LocalBackupAvailability.deletionPending,
    );
    for (final e in autos.skip(1)) {
      await const SqliteLocalBackupValidator().validate(image(e.backupId).path);
    }
    persistence = _Persistence();
    expect((await manager().retryPendingDeletions()).deletedBackupIds, [
      autos.first.backupId,
    ]);
    await checkIds(autos.skip(1).map((e) => e.backupId));
  });

  test('baja durable impide resurrección desde slot viejo y escaneo de copia final', () async {
    final autos = await automatics(4);
    final old = await catalog();
    persistence.failDelete = true;
    await confirm(4);
    await writeSlots(old);
    final listing = await manager().read();
    expect(
      listing.entries
          .singleWhere((e) => e.backupId == autos.first.backupId)
          .availability,
      LocalBackupAvailability.deletionPending,
    );
    expect(listing.pruningAllowed, false);
  });

  for (final point in [1, 2]) {
    test(
      'reinicio tras $point archivos eliminados no resucita; reintento completa',
      () async {
        final autos = await automatics(4);
        if (point == 1) {
          persistence.failAfterDelete = 1;
        } else {
          persistence.failCatalogCommit = 3;
        } // validation, deletionPending, removal
        await confirm(4);
        persistence = _Persistence();
        final result = await manager().retryPendingDeletions();
        expect(result.deletedBackupIds, [autos.first.backupId]);
        await checkIds(autos.skip(1).map((e) => e.backupId));
      },
    );
  }

  test(
    'interrupción entre baja y catálogo no elimina bytes y se recupera',
    () async {
      final autos = await automatics(4);
      persistence.failCatalogCommit = 2;
      final result = await confirm(4);
      expect(result.deletedBackupIds, isEmpty);
      expect(persistence.deletes, 0);
      expect(await tombstone(autos.first.backupId).exists(), true);
      persistence = _Persistence();
      expect(
        (await manager().read()).entries
            .singleWhere((e) => e.backupId == autos.first.backupId)
            .availability,
        LocalBackupAvailability.deletionPending,
      );
      expect((await manager().retryPendingDeletions()).deletedBackupIds, [
        autos.first.backupId,
      ]);
    },
  );

  for (final point in ['write', 'flush']) {
    test('espacio/escritura $point no borra manuales ni automáticas', () async {
      final manual = await creator().createManual();
      final autos = await automatics(4);
      final bytes = await image(manual.backupId).readAsBytes();
      persistence.failWrite = point == 'write';
      persistence.failFlush = point == 'flush';
      final result = await confirm(4);
      expect(result.deletedBackupIds, isEmpty);
      expect(persistence.deletes, 0);
      expect(
        result.incidents.any(
          (i) => i.issue == LocalBackupCatalogIssue.storageFailure,
        ),
        true,
      );
      expect(await image(manual.backupId).readAsBytes(), bytes);
      for (final e in autos) {
        expect(await image(e.backupId).exists(), true);
      }
    });
  }

  test('baja corrupta bloquea nuevos borrados y reintentos', () async {
    final autos = await automatics(4);
    persistence.failDelete = true;
    await confirm(4);
    await tombstone(autos.first.backupId).writeAsString('{truncated');
    persistence = _Persistence();
    expect((await confirm(4)).deletedBackupIds, isEmpty);
    expect((await manager().retryPendingDeletions()).deletedBackupIds, isEmpty);
    expect(
      (await manager().read()).entries
          .singleWhere((e) => e.backupId == autos.first.backupId)
          .availability,
      LocalBackupAvailability.quarantined,
    );
    expect(persistence.deletes, 0);
  });

  test(
    'un slot corrupto se aísla y repara conservando epoch y señal',
    () async {
      final m = await creator().createManual();
      final previous = await catalog();
      await slot('a').writeAsString('damaged');
      final listing = await manager().read();
      expect(listing.status, LocalBackupCatalogStatus.recovered);
      expect(listing.entries.single.backupId, m.backupId);
      expect(
        (await catalog())['localRestoreEpoch'],
        previous['localRestoreEpoch'],
      );
      expect(
        (await Directory(p.join(base(), 'diagnostics')).list().toList()),
        hasLength(1),
      );
      expect((await creator().createManual()).creationOrder, 2);
    },
  );

  test('ambos slots corruptos: reconstrucción pending sin abrir SQLite, epoch nuevo', () async {
    final m = await creator().createManual();
    final previous = await catalog();
    for (final name in ['a', 'b']) {
      await slot(name).writeAsString('damaged');
    }
    final listing = await manager().read();
    expect(listing.status, LocalBackupCatalogStatus.recovered);
    expect(listing.entries.single.backupId, m.backupId);
    expect(
      listing.entries.single.validation,
      LocalBackupValidationState.pending,
    );
    expect(validator.calls, 0);
    final rebuilt = await catalog();
    expect(rebuilt['localRestoreEpoch'], isNot(previous['localRestoreEpoch']));
    expect(rebuilt['syncContrastRequired'], true);
    expect(rebuilt['nextCreationOrder'], '2');
    expect(
      (await Directory(p.join(base(), 'diagnostics')).list().toList()),
      hasLength(2),
    );
  });

  test(
    'generación igual conflictiva no elige por fecha; reconstruye pending',
    () async {
      final m = await creator().createManual();
      final a = await catalog();
      await writeSlots(a);
      final b = decodeBackupEnvelope(await slot('b').readAsBytes());
      b['syncContrastRequired'] = false;
      await slot('b').writeAsBytes(encodeBackupEnvelope(b));
      final listing = await manager().read();
      expect(listing.status, LocalBackupCatalogStatus.recovered);
      expect(
        listing.entries.single.validation,
        LocalBackupValidationState.pending,
      );
      expect(listing.entries.single.backupId, m.backupId);
      expect((await catalog())['syncContrastRequired'], true);
    },
  );

  test(
    'final no registrado se reconcilia pending; .next no se adopta',
    () async {
      final m = await creator().createManual();
      final old = await catalog();
      old['entries'] = [];
      await writeSlots(old);
      await File(p.join(base(), 'catalog-${operation(99)}.next'))
          .writeAsString('truncated');
      final listing = await manager().read();
      expect(listing.entries.single.backupId, m.backupId);
      expect(
        listing.entries.single.validation,
        LocalBackupValidationState.pending,
      );
      expect(
        listing.incidents.single.issue,
        LocalBackupCatalogIssue.catalogWritePending,
      );
      expect(validator.calls, 0);
    },
  );

  test(
    'futuro slot preservado: incompatible sin reemplazar desde antiguo',
    () async {
      await creator().createManual();
      final future = await catalog();
      future['formatVersion'] = 2;
      await slot('a').writeAsBytes(encodeBackupEnvelope(future));
      final a = await slot('a').readAsBytes();
      final b = await slot('b').readAsBytes();
      expect(
        (await manager().read()).status,
        LocalBackupCatalogStatus.incompatible,
      );
      expect(await slot('a').readAsBytes(), a);
      expect(await slot('b').readAsBytes(), b);
      expect((await confirm(1)).deletedBackupIds, isEmpty);
    },
  );

  test('fallo I/O se informa unavailable, nunca empty', () async {
    final catalog = LocalBackupCatalogService(
      supportDirectory: () async =>
          throw const FileSystemException('unreadable'),
      validator: validator,
    );
    final listing = await catalog.read();
    expect(listing.status, LocalBackupCatalogStatus.unavailable);
    expect(listing.pruningAllowed, false);
    expect(
      listing.incidents.single.issue,
      LocalBackupCatalogIssue.storageFailure,
    );
  });

  test('ausente conserva metadatos conocidos; hash distinto revoca validación histórica', () async {
    final missing = await creator().createManual();
    final changed = await creator().createManual();
    // Synthetic fixture removal only; production always uses tombstones.
    await artifact(missing.backupId).delete(recursive: true);
    await corrupt(changed.backupId);
    final listing = await manager().read();
    final a = listing.entries.singleWhere(
      (e) => e.backupId == missing.backupId,
    );
    expect(a.availability, LocalBackupAvailability.missing);
    expect(a.origin, LocalBackupOrigin.manual);
    final b = listing.entries.singleWhere(
      (e) => e.backupId == changed.backupId,
    );
    expect(b.validation, LocalBackupValidationState.invalid);
    expect(b.issue, 'hashMismatch');
    expect(validator.calls, 0);
  });

  test('incompletos, intent verificable y snapshot huérfano separados; orden no reutilizado', () async {
    await creator().createManual();
    final id = operation(70);
    final stage = Directory(p.join(base(), 'staging', id));
    await stage.create();
    final intent = {
      'kind': 'autofinance.localBackupIntent',
      'formatVersion': 1,
      'backupId': id,
      'creationOrder': '10',
      'origin': 'preRestore',
      'restoreOperationId': operation(70),
      'requestedAtUtc': backupUtc(clock),
    };
    await File(p.join(stage.path, 'intent.json'))
        .writeAsBytes(encodeBackupEnvelope(intent));
    await File(p.join(stage.path, 'autofinance.sqlite.part'))
        .writeAsString('partial');
    final orphan = Directory(p.join(root(), 'copies', 'snapshot-unknown'));
    await orphan.create(recursive: true);
    await File(p.join(orphan.path, 'autofinance.sqlite'))
        .writeAsString('unknown');
    final listing = await manager().read();
    expect(listing.entries, hasLength(1));
    expect(listing.pruningAllowed, false);
    expect(
      listing.incidents.singleWhere((i) => i.backupId == id).origin,
      LocalBackupOrigin.preRestore,
    );
    expect(
      listing.incidents
          .singleWhere((i) => i.issue == LocalBackupCatalogIssue.orphan)
          .origin,
      null,
    );
    expect((await catalog())['nextCreationOrder'], '11');
  });

  test('origen/orden contradictorio en intent suspende poda', () async {
    final autos = await automatics(4);
    final id = autos.first.backupId;
    final stage = Directory(p.join(base(), 'staging', id));
    await stage.create();
    await File(p.join(stage.path, 'intent.json')).writeAsBytes(
      encodeBackupEnvelope({
        'kind': 'autofinance.localBackupIntent',
        'formatVersion': 1,
        'backupId': id,
        'creationOrder': '2',
        'origin': 'manual',
        'restoreOperationId': null,
        'requestedAtUtc': backupUtc(clock),
      }),
    );
    expect((await confirm(4)).deletedBackupIds, isEmpty);
    expect(persistence.deletes, 0);
  });

  test('exclusión con creador comparte bloqueo nativo', () async {
    await creator().createManual();
    await NativeBackupPersistence().exclusively(
      p.join(root(), '.local-backups.lock'),
      () async {
        await expectLater(
          manager().read(),
          throwsA(
            isA<LocalBackupFailure>().having(
              (e) => e.code,
              'code',
              LocalBackupFailureCode.operationInProgress,
            ),
          ),
        );
        await expectLater(
          confirm(1),
          throwsA(
            isA<LocalBackupFailure>().having(
              (e) => e.code,
              'code',
              LocalBackupFailureCode.operationInProgress,
            ),
          ),
        );
      },
    );
  });

  test(
    'reparación sin espacio conserva listado diagnóstico y copia utilizable',
    () async {
      final m = await creator().createManual();
      await slot('a').writeAsString('damaged');
      persistence.failFlush = true;
      final listing = await manager().read();
      expect(listing.status, LocalBackupCatalogStatus.unavailable);
      expect(listing.entries.single.backupId, m.backupId);
      expect(listing.pruningAllowed, false);
      expect(
        listing.incidents.any(
          (i) => i.issue == LocalBackupCatalogIssue.storageFailure,
        ),
        true,
      );
      await const SqliteLocalBackupValidator().validate(image(m.backupId).path);
      expect(persistence.deletes, 0);
    },
  );

  test(
    'fichero huérfano suelto no oculta entradas ni se valida como copia',
    () async {
      final m = await creator().createManual();
      await File(p.join(root(), 'copies', 'unknown.part'))
          .writeAsString('partial');
      final listing = await manager().read();
      expect(listing.entries.single.backupId, m.backupId);
      expect(listing.incidents.single.issue, LocalBackupCatalogIssue.orphan);
      expect(listing.pruningAllowed, false);
    },
  );

  test(
    'descriptor final con orden repetido queda como incidencia, sin renumerar',
    () async {
      final autos = await automatics(4);
      final newId = operation(80);
      final directory = artifact(newId);
      await directory.create();
      await image(autos.first.backupId).copy(image(newId).path);
      final d = decodeBackupEnvelope(
        await File(p.join(artifact(autos.first.backupId).path, 'manifest.json'))
            .readAsBytes(),
      );
      d['backupId'] = newId;
      await File(p.join(directory.path, 'manifest.json'))
          .writeAsBytes(encodeBackupEnvelope(d));
      final listing = await manager().read();
      expect(listing.entries, hasLength(4));
      expect(
        listing.incidents.any(
          (i) => i.issue == LocalBackupCatalogIssue.ambiguousOrder,
        ),
        true,
      );
      expect((await confirm(4)).deletedBackupIds, isEmpty);
      expect(await image(newId).exists(), true);
    },
  );

  test(
    'baja contradictoria por retención de manual no autoriza borrado',
    () async {
      final m = await creator().createManual();
      await creator().createManual();
      await Directory(p.join(base(), 'tombstones')).create();
      await tombstone(m.backupId).writeAsBytes(
        encodeBackupEnvelope({
          'kind': 'autofinance.localBackupDeletion',
          'formatVersion': 1,
          'backupId': m.backupId,
          'creationOrder': '${m.creationOrder}',
          'deletedAtUtc': backupUtc(clock),
          'reason': 'retention',
          'restoreOperationId': operation(1),
        }),
      );
      expect(
        (await manager().retryPendingDeletions()).deletedBackupIds,
        isEmpty,
      );
      expect(
        (await manager().read()).entries
            .singleWhere((e) => e.backupId == m.backupId)
            .availability,
        LocalBackupAvailability.quarantined,
      );
      expect(await image(m.backupId).exists(), true);
    },
  );

  test('no sigue enlace al borrar; bytes ajenos conservados', () async {
    final autos = await automatics(4);
    final external = File(p.join(support.path, 'outside.txt'));
    await external.writeAsString('protected');
    final alias = Link(
      p.join(artifact(autos.first.backupId).path, 'extra-link'),
    );
    // Windows requires Developer Mode for symlinks; a junction exercises the
    // same path boundary without that privilege. Both paths are test fixtures.
    if (Platform.isWindows) {
      final linkPath = alias.path.replaceAll("'", "''");
      final targetPath = support.path.replaceAll("'", "''");
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "New-Item -ItemType Junction -Path '$linkPath' -Target '$targetPath' -ErrorAction Stop | Out-Null",
      ]);
      expect(result.exitCode, 0, reason: 'Crear junction sintético');
    } else {
      await alias.create(support.path);
    }
    try {
      expect((await confirm(4)).deletedBackupIds, isEmpty);
      expect(await external.readAsString(), 'protected');
      expect(persistence.deletes, 0);
    } finally {
      if (Platform.isWindows) {
        await Directory(alias.path).delete();
      } else {
        await alias.delete();
      }
    }
  });

  test('cambio de manifiesto durante revalidación suspende poda', () async {
    final autos = await automatics(4);
    validator.before = (path) async {
      if (p.basename(p.dirname(path)) == autos.last.backupId) {
        await File(p.join(artifact(autos.last.backupId).path, 'manifest.json'))
            .writeAsString('damaged');
      }
    };
    expect((await confirm(4)).deletedBackupIds, isEmpty);
    expect(persistence.deletes, 0);
  });

  test(
    'reintento de retención exige otra vez tres automáticas válidas',
    () async {
      final autos = await automatics(4);
      persistence.failDelete = true;
      await confirm(4);
      await corrupt(autos[2].backupId);
      await corrupt(autos[3].backupId);
      persistence = _Persistence();
      final result = await manager().retryPendingDeletions();
      expect(result.deletedBackupIds, isEmpty);
      expect(
        result.incidents.any(
          (i) => i.issue == LocalBackupCatalogIssue.insufficientValidBackups,
        ),
        true,
      );
      await const SqliteLocalBackupValidator().validate(
        image(autos.first.backupId).path,
      );
      expect(persistence.deletes, 0);
    },
  );
}
