import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/bootstrap.dart';
import 'package:myautofinance/app/local_backup_session.dart';
import 'package:myautofinance/app/local_backup_factory.dart';
import 'package:myautofinance/core/config/app_config.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  late LocalBackupSession session;
  setUp(() async {
    support = await Directory.systemTemp.createTemp('autofinance-ui-session-');
    session = LocalBackupSession(supportDirectory: () async => support);
    expect(await session.open(), isTrue);
    final db = await session.store.open();
    await db.customStatement(
      "INSERT INTO categories(id,name,is_income,created_at,updated_at) VALUES('11111111-1111-4111-8111-111111111111','Estado de copia',0,'2026-10-02T12:00:00.000Z','2026-10-02T12:00:00.000Z')",
    );
    await session.controller.create();
    expect(session.controller.error, isNull);
    expect(session.controller.listing!.entries, hasLength(1));
  });
  tearDown(() async {
    await session.store.close();
    session.controller.dispose();
    await support.delete(recursive: true);
  });

  test('Servicios reales: cancelar conserva cambios, restaurar protege y anuncia contraste', () async {
    final selected = session.controller.listing!.entries.single.backupId;
    final db = await session.store.open();
    await db.writeTransaction(() async {
      await db.customStatement("UPDATE categories SET name='Estado posterior'");
    });
    await session.controller.restore(selected, confirmed: false);
    expect(
      (await db.customSelect('SELECT name FROM categories').getSingle())
          .data['name'],
      'Estado posterior',
    );
    expect(session.controller.restoreResult, isNull);
    await session.controller.restore(selected, confirmed: true);
    expect(
      session.controller.restoreResult!.status,
      LocalRestoreStatus.restored,
    );
    expect(session.controller.restoreResult!.previousBackupId, isNotNull);
    final restored = await session.store.open();
    expect(
      (await restored.customSelect('SELECT name FROM categories').getSingle())
          .data['name'],
      'Estado de copia',
    );
    expect(session.controller.listing!.entries, hasLength(2));
    // La señal duradera procede de la restauración, no de la pantalla.
    final contrast = await createLocalSyncContrastReader(
      supportDirectory: () async => support,
    ).read();
    expect(contrast.required, isTrue);
    expect(contrast.restoreEpoch, isNotEmpty);
  });

  test(
    'Base ilegible: bootstrap conserva catálogo y restaura aislando originales',
    () async {
      final selected = session.controller.listing!.entries.single.backupId;
      await session.store.close();
      session.controller.dispose();
      final active = File(p.join(support.path, 'sqlite', 'autofinance.sqlite'));
      await active.writeAsString('BASE DAÑADA SINTÉTICA', flush: true);
      session = LocalBackupSession(supportDirectory: () async => support);
      final app = await initializeApp(
        initialize: () async =>
            const AppConfig(environment: AppEnvironment.test),
        initializeLocal: () async {
          expect(await session.open(), isFalse);
          return session;
        },
      );
      expect(app, isA<AutofinanceApp>());
      expect(session.controller.activeAvailable, isFalse);
      await session.controller.refresh();
      expect(session.controller.listing!.entries.single.backupId, selected);
      await session.controller.restore(selected, confirmed: true);
      expect(
        session.controller.restoreResult!.status,
        LocalRestoreStatus.restored,
      );
      expect(session.controller.restoreResult!.previousBackupId, isNull);
      expect(session.controller.activeAvailable, isTrue);
      expect(session.controller.listing!.entries, hasLength(1));
      final originals = await support
          .list(recursive: true)
          .where(
            (entry) =>
                entry is File &&
                entry.path.contains('previous') &&
                entry.path.endsWith('autofinance.sqlite'),
          )
          .cast<File>()
          .toList();
      expect(originals, isNotEmpty);
      expect(await originals.first.readAsString(), 'BASE DAÑADA SINTÉTICA');
      final restored = await session.store.open();
      expect(
        (await restored.customSelect('SELECT name FROM categories').getSingle())
            .data['name'],
        'Estado de copia',
      );
    },
  );

  test('Una copia alterada es rechazada antes del intercambio desde el controlador', () async {
    final selected = session.controller.listing!.entries.single.backupId;
    final file = File(
      p.join(
        support.path,
        'sqlite',
        'local-backups',
        'backups',
        selected,
        'autofinance.sqlite',
      ),
    );
    final bytes = await file.readAsBytes();
    bytes[100] ^= 1;
    await file.writeAsBytes(bytes, flush: true);
    await session.controller.restore(selected, confirmed: true);
    expect(
      session.controller.restoreResult!.status,
      LocalRestoreStatus.rejected,
    );
    expect(
      session.controller.restoreResult!.candidateIssue,
      LocalRestoreCandidateIssue.hashMismatch,
    );
    expect(session.controller.error, contains('ha cambiado'));
    final db = await session.store.open();
    expect(
      (await db.customSelect('SELECT name FROM categories').getSingle())
          .data['name'],
      'Estado de copia',
    );
  });
}
