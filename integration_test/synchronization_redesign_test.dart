import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/local_backup_session.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/features/synchronization/domain/drive_download.dart';
import 'package:myautofinance/features/synchronization/domain/drive_download_application.dart';
import 'package:myautofinance/features/synchronization/domain/drive_metadata.dart';
import 'package:myautofinance/features/synchronization/domain/drive_transfer.dart';
import 'package:myautofinance/features/synchronization/domain/drive_upload.dart';
import 'package:myautofinance/features/synchronization/domain/installation_sync_state.dart';
import 'package:myautofinance/features/synchronization/domain/local_restore.dart';
import 'package:myautofinance/features/synchronization/presentation/drive_controller.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../test/support/app_navigation.dart';

// Remote ports use synthetic responses. Local copy/restore uses real SQLite
// and the production coordinators in an isolated, disposable installation.
class _Remote implements DriveUploader, DriveDownloadApplication {
  int uploads = 0;
  int downloads = 0;
  final metadata = DriveFileMetadata(
    id: 'synthetic-file',
    name: 'autofinance.sqlite',
    mimeType: 'application/octet-stream',
    parents: ['synthetic-folder'],
    trashed: false,
    version: '7',
    modifiedTime: DateTime.utc(2026, 10, 2, 12),
  );
  @override
  Future<DriveUploadResult> upload({
    required DriveTransferCancellation cancellation,
    void Function(DriveTransferProgress)? onProgress,
  }) async {
    uploads++;
    return DriveUploadResult(DriveUploadStatus.divergence, remote: metadata);
  }

  @override
  Future<DriveDownloadApplicationResult> downloadAndApply({
    required DriveTransferCancellation cancellation,
    required Future<bool> Function(DriveDownloadReview) review,
    void Function(DriveTransferProgress)? onProgress,
    void Function()? onApplying,
  }) async {
    downloads++;
    final accepted = await review(
      DriveDownloadReview(
        accountId: 'synthetic-account',
        remote: metadata,
        localStatus: SyncLocalStatus.changed,
      ),
    );
    expect(accepted, false);
    return const DriveDownloadApplicationResult(
      DriveDownloadApplicationStatus.cancelled,
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Drive pasivo, cancelación y recuperación SQLite en UI nativa', (
    tester,
  ) async {
    final support = await getApplicationSupportDirectory();
    final fixtures = await Directory(
      p.join(support.path, 'synchronization-redesign-tests'),
    ).create(recursive: true);
    final temporary = await fixtures.createTemp('synthetic-216-');
    // Android exposes /data/user/0 and /data/data aliases for the same private
    // directory. The production persistence contract expects canonical paths.
    final fixture = Directory(await temporary.resolveSymbolicLinks());
    final session = LocalBackupSession(supportDirectory: () async => fixture);
    final remote = _Remote();
    var preparations = 0;
    final drive = DriveController(
      uploader: remote,
      downloader: remote,
      prepare: (_) async {
        preparations++;
        return null;
      },
      readLocal: () async => DriveViewSnapshot(
        account: 'persona@example.invalid',
        referenceVersion: '5',
        version: '5',
        date: DateTime.utc(2026, 10, 1, 9),
        localStatus: SyncLocalStatus.changed,
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    Future<void> tap(String text) async {
      final dialog = find.byType(AlertDialog);
      final finder = dialog.evaluate().isEmpty
          ? find.text(text).first
          : find.descendant(of: dialog, matching: find.text(text)).first;
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await settle();
    }

    Future<void> capture(String name) async {
      if (!const bool.fromEnvironment('CAPTURE_SYNC_REDESIGN')) return;
      final output = const String.fromEnvironment('SYNC_CAPTURE_DIRECTORY');
      final directory = await Directory(
        output.isEmpty
            ? p.join(support.path, 'synchronization-redesign-captures')
            : output,
      ).create(recursive: true);
      await tester.pump();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('native-sync-capture')),
      );
      final picture = await boundary.toImage();
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        p.join(
          directory.path,
          '${Platform.isWindows ? 'windows' : 'android'}-$name.png',
        ),
      );
      await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
      picture.dispose();
      // Only the isolated capture directory is printed, never user data.
      debugPrint('SYNC_CAPTURE: ${file.path}');
    }

    try {
      // Surface the real startup cause rather than the UI's recovery boolean.
      await session.store.open();
      expect(await session.open(), true);
      final database = await session.store.open();
      await database.customStatement(
        "INSERT INTO categories(id,name,is_income,created_at,updated_at) "
        "VALUES('11111111-1111-4111-8111-111111111111','Categoría sintética',0,"
        "'2026-10-02T12:00:00.000Z','2026-10-02T12:00:00.000Z')",
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('native-sync-capture'),
          child: AutofinanceApp(localBackups: session.controller, drive: drive),
        ),
      );
      await settle();
      expect(preparations, 0);
      await selectAppDestination(tester, SessionDestination.management);
      await tap('Copia en Drive');
      expect(preparations, 0);
      expect(remote.uploads + remote.downloads, 0);
      await capture('drive');
      await tap('Subir copia');
      expect(find.text('Copias divergentes'), findsWidgets);
      expect(find.textContaining('Versión 7'), findsOneWidget);
      await capture('divergencia');
      await tap('Descargar última copia');
      expect(find.byType(AlertDialog), findsOneWidget);
      await capture('confirmacion-drive');
      await tap('Cancelar');
      expect(
        (await database.customSelect('SELECT name FROM categories').getSingle())
            .data['name'],
        'Categoría sintética',
      );
      await tap('Abrir Copias locales');
      await tap('Crear copia');
      await tap('Cancelar');
      expect(session.controller.listing!.entries, isEmpty);
      await tap('Crear copia');
      await tap('Crear copia');
      expect(session.controller.listing!.entries, hasLength(1));
      await capture('catalogo');
      await database.writeTransaction(() async {
        await database.customStatement(
          "UPDATE categories SET name='Cambio posterior sintético'",
        );
      });
      await tap('Ver detalle');
      await tap('Restaurar esta copia');
      await capture('confirmacion-local');
      await tap('Cancelar');
      expect(
        (await database.customSelect('SELECT name FROM categories').getSingle())
            .data['name'],
        'Cambio posterior sintético',
      );
      await tap('Restaurar esta copia');
      await tap('Entiendo que la base activa volverá a esta fecha.');
      await tap('Restaurar copia');
      expect(
        session.controller.restoreResult!.status,
        LocalRestoreStatus.restored,
      );
      expect(session.controller.restoreResult!.previousBackupId, isNotNull);
      expect(session.controller.listing!.entries, hasLength(2));
      final restored = await session.store.open();
      expect(
        (await restored.customSelect('SELECT name FROM categories').getSingle())
            .data['name'],
        'Categoría sintética',
      );
      await capture('restaurada');
      expect(remote.uploads, 1);
      expect(remote.downloads, 1);
      expect(preparations, 2);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await session.store.close();
      session.controller.dispose();
      drive.dispose();
      final fixtureRoot = await fixtures.resolveSymbolicLinks();
      final fixturePath = await fixture.resolveSymbolicLinks();
      if (!p.isWithin(fixtureRoot, fixturePath)) {
        throw StateError('Fixture fuera de su ámbito');
      }
      await Directory(fixturePath).delete(recursive: true);
    }
  });
}
