import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';

import '../support/app_navigation.dart';

import 'package:myautofinance/features/synchronization/domain/drive_download.dart';
import 'package:myautofinance/features/synchronization/domain/drive_download_application.dart';
import 'package:myautofinance/features/synchronization/domain/drive_metadata.dart';
import 'package:myautofinance/features/synchronization/domain/drive_transfer.dart';
import 'package:myautofinance/features/synchronization/domain/drive_upload.dart';
import 'package:myautofinance/features/synchronization/domain/installation_sync_state.dart';
import 'package:myautofinance/features/synchronization/domain/local_restore.dart';
import 'package:myautofinance/features/synchronization/domain/local_restore_candidate.dart';
import 'package:myautofinance/features/synchronization/presentation/drive_controller.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

DriveFileMetadata remote() => DriveFileMetadata(
  id: 'synthetic-copy',
  name: 'autofinance.sqlite',
  mimeType: 'application/octet-stream',
  parents: ['folder'],
  trashed: false,
  version: '7',
  modifiedTime: DateTime.utc(2026, 10, 2, 12),
);

class Uploader implements DriveUploader {
  int calls = 0;
  DriveUploadStatus status = DriveUploadStatus.uploaded;
  DriveTransferFailure? failure;
  Completer<void>? wait;
  @override
  Future<DriveUploadResult> upload({
    required DriveTransferCancellation cancellation,
    void Function(DriveTransferProgress)? onProgress,
  }) async {
    calls++;
    onProgress?.call(
      const DriveTransferProgress(1, 2, DriveTransferPhase.transferring),
    );
    if (wait != null) {
      await Future.any([wait!.future, cancellation.whenCancelled]);
    }
    return DriveUploadResult(
      cancellation.isCancelled ? DriveUploadStatus.cancelled : status,
      transferFailure: failure,
      remote: status == DriveUploadStatus.uploaded && !cancellation.isCancelled
          ? remote()
          : null,
    );
  }
}

class Downloader implements DriveDownloadApplication {
  int calls = 0;
  int applied = 0;
  DriveDownloadApplicationStatus status =
      DriveDownloadApplicationStatus.downloaded;
  DriveDownloadStatus? rejection;
  SyncLocalStatus localStatus = SyncLocalStatus.changed;
  LocalRestoreResult? restoreFailure;
  Completer<void>? wait;
  @override
  Future<DriveDownloadApplicationResult> downloadAndApply({
    required DriveTransferCancellation cancellation,
    required Future<bool> Function(DriveDownloadReview) review,
    void Function()? onApplying,
    void Function(DriveTransferProgress)? onProgress,
  }) async {
    calls++;
    if (rejection != null) {
      return DriveDownloadApplicationResult(
        DriveDownloadApplicationStatus.downloadRejected,
        download: DriveDownloadResult(rejection!),
      );
    }
    final accepted = await review(
      DriveDownloadReview(
        accountId: 'synthetic-account',
        remote: remote(),
        localStatus: localStatus,
      ),
    );
    if (!accepted || cancellation.isCancelled) {
      return const DriveDownloadApplicationResult(
        DriveDownloadApplicationStatus.cancelled,
      );
    }
    onApplying?.call();
    if (wait != null) {
      await Future.any([wait!.future, cancellation.whenCancelled]);
    }
    if (cancellation.isCancelled) {
      return const DriveDownloadApplicationResult(
        DriveDownloadApplicationStatus.cancelled,
      );
    }
    if (status == DriveDownloadApplicationStatus.downloaded) applied++;
    return DriveDownloadApplicationResult(
      status,
      remote: status == DriveDownloadApplicationStatus.downloaded
          ? remote()
          : null,
      restore:
          restoreFailure ??
          (status == DriveDownloadApplicationStatus.downloaded
              ? const LocalRestoreResult(
                  LocalRestoreStatus.restored,
                  previousBackupId: 'respaldo-sintetico',
                )
              : null),
    );
  }
}

DriveController controller(Uploader upload, Downloader download) =>
    DriveController(
      uploader: upload,
      downloader: download,
      prepare: (_) async => null,
      readLocal: () async => const DriveViewSnapshot(
        account: 'prueba@example.invalid',
        localStatus: SyncLocalStatus.changed,
      ),
    );

Future<void> open(WidgetTester tester, DriveController drive) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('drive-capture'),
      child: AutofinanceApp(drive: drive),
    ),
  );
  await selectAppDestination(tester, SessionDestination.management);
  await tester.ensureVisible(find.text('Copia en Drive'));
  await tapVisible(tester, find.text('Copia en Drive'));
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
}

void main() {
  testWidgets(
    'cambiar de cuenta descarta versión y fecha observadas anteriores',
    (tester) async {
      var account = 'primera@example.invalid';
      var preparations = 0;
      final drive = DriveController(
        uploader: Uploader(),
        downloader: Downloader(),
        prepare: (_) async {
          preparations++;
          return null;
        },
        readLocal: () async => DriveViewSnapshot(account: account),
      );
      await open(tester, drive);
      await tapVisible(tester, find.text('Subir copia'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Versión 7'), findsOneWidget);
      account = 'segunda@example.invalid';
      await drive.refreshLocal();
      await tester.pumpAndSettle();
      expect(find.textContaining('Remoto desconocido'), findsOneWidget);
      expect(find.textContaining('Versión 7'), findsNothing);
      expect(find.textContaining('02/10/2026'), findsNothing);
      expect(preparations, 1);
    },
  );

  for (final issue in [
    DriveMetadataIssue.credentialExpired,
    DriveMetadataIssue.networkFailure,
  ]) {
    testWidgets('subida fallida identifica $issue sin anunciar éxito', (
      tester,
    ) async {
      final upload = Uploader()
        ..status = DriveUploadStatus.failed
        ..failure = DriveTransferFailure(
          DriveTransferIssue.remoteFailure,
          remoteFailure: DriveMetadataFailure(issue),
        );
      final drive = controller(upload, Downloader());
      await open(tester, drive);
      await tapVisible(tester, find.text('Subir copia'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          issue == DriveMetadataIssue.credentialExpired
              ? 'Revisa la autorización de la cuenta.'
              : 'Comprueba la conexión.',
        ),
        findsOneWidget,
      );
      expect(find.text('Completado'), findsNothing);
      expect(drive.completed, false);
    });
  }

  testWidgets('versiones conocidas divergentes y acceso local sin red', (
    tester,
  ) async {
    final upload = Uploader();
    final download = Downloader();
    var preparations = 0;
    final drive = DriveController(
      uploader: upload,
      downloader: download,
      prepare: (_) async {
        preparations++;
        return null;
      },
      readLocal: () async => DriveViewSnapshot(
        account: 'prueba@example.invalid',
        version: '7',
        referenceVersion: '5',
        date: DateTime.utc(2026, 10, 2, 12),
        localStatus: SyncLocalStatus.changed,
      ),
    );
    await open(tester, drive);
    expect(find.text('Copias divergentes'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.textContaining('Versión 7'), findsOneWidget);
    expect(find.textContaining('02/10/2026'), findsOneWidget);
    await tapVisible(tester, find.text('Abrir Copias locales'));
    await tester.pumpAndSettle();
    expect(preparations, 0);
    expect(upload.calls, 0);
    expect(download.calls, 0);
    expect(find.text('Tu base local'), findsNothing);
  });

  testWidgets('sin copia no reutiliza fecha ni versión de una copia anterior', (
    tester,
  ) async {
    final download = Downloader()..rejection = DriveDownloadStatus.noCopy;
    final drive = DriveController(
      uploader: Uploader(),
      downloader: download,
      prepare: (_) async => null,
      readLocal: () async => DriveViewSnapshot(
        version: '7',
        referenceVersion: '7',
        date: DateTime.utc(2026, 10, 2),
      ),
    );
    await open(tester, drive);
    await tapVisible(tester, find.text('Descargar última copia'));
    await tester.pumpAndSettle();
    expect(find.text('Sin copia en Drive'), findsOneWidget);
    expect(find.textContaining('02/10/2026'), findsNothing);
    expect(find.textContaining('Versión 7'), findsNothing);
    expect(find.text('Completado'), findsNothing);
  });

  for (final status in SyncLocalStatus.values) {
    testWidgets('estado local $status visible sin consulta remota', (
      tester,
    ) async {
      var preparations = 0;
      final drive = DriveController(
        uploader: Uploader(),
        downloader: Downloader(),
        prepare: (_) async {
          preparations++;
          return null;
        },
        readLocal: () async => DriveViewSnapshot(localStatus: status),
      );
      await open(tester, drive);
      expect(find.textContaining('Cambios locales:'), findsOneWidget);
      expect(preparations, 0);
      expect(find.byType(AfCard), findsWidgets);
    });
  }

  testWidgets('fallo de respaldo conserva la causa y no anuncia éxito', (
    tester,
  ) async {
    final download = Downloader()
      ..status = DriveDownloadApplicationStatus.failed
      ..restoreFailure = const LocalRestoreResult(
        LocalRestoreStatus.rejected,
        candidateIssue: LocalRestoreCandidateIssue.storageFailure,
      );
    final drive = controller(Uploader(), download);
    await open(tester, drive);
    await tapVisible(tester, find.text('Descargar última copia'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Descargar y sustituir'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(LocalRestoreCandidateIssue.storageFailure.message),
      findsOneWidget,
    );
    expect(find.text('Completado'), findsNothing);
    expect(drive.completed, false);
    expect(download.applied, 0);
  });

  testWidgets('progreso real por fase sin porcentaje y cancelación sin éxito', (
    tester,
  ) async {
    final upload = Uploader()..wait = Completer<void>();
    final drive = controller(upload, Downloader());
    await open(tester, drive);
    await tapVisible(tester, find.text('Subir copia'));
    await tester.pump();
    expect(find.text('Subiendo copia'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );
    await tapVisible(tester, find.text('Cancelar operación'));
    await tester.pumpAndSettle();
    expect(find.text('Completado'), findsNothing);
    expect(drive.completed, false);
  });

  if (const bool.fromEnvironment('CAPTURE_DRIVE_UI')) {
    for (final size in [
      const Size(1440, 900),
      const Size(412, 915),
      const Size(320, 800),
    ]) {
      testWidgets(
        'captura de implementación $size',
        (tester) async {
          await tester.runAsync(() async {
            final loader = FontLoader(
              size.width >= 840 ? 'Segoe UI' : 'Roboto',
            );
            final bytes = await File(
              size.width >= 840 ? 'C:/Windows/Fonts/segoeui.ttf' : '.tools/flutter/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
            ).readAsBytes();
            loader.addFont(Future.value(ByteData.sublistView(bytes)));
            await loader.load();
          });
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = size.width == 320
              ? 2
              : 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final drive = controller(Uploader(), Downloader());
          await open(tester, drive);
          Future<void> capture(String state) async {
            await tester.runAsync(() async {
              final render = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('drive-capture')),
              );
              final picture = await render.toImage();
              final bytes = await picture.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File('.tools/068-${size.width.toInt()}-$state.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              picture.dispose();
            });
          }

          await capture('reposo');
          await tester.ensureVisible(find.text('Descargar última copia'));
          await tapVisible(tester, find.text('Descargar última copia'));
          await tester.pumpAndSettle();
          await capture('confirmacion');
          await tester.ensureVisible(find.text('Cancelar'));
          await tapVisible(tester, find.text('Cancelar'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(
          size.width >= 840 ? TargetPlatform.windows : TargetPlatform.android,
        ),
      );
    }
  }
  testWidgets(
    'entrar y volver no consulta ni transfiere; remoto desconocido se distingue de sin copia',
    (tester) async {
      final upload = Uploader();
      final download = Downloader();
      final drive = controller(upload, download);
      await open(tester, drive);
      expect(upload.calls, 0);
      expect(download.calls, 0);
      expect(find.textContaining('Remoto desconocido'), findsOneWidget);
      download.rejection = DriveDownloadStatus.noCopy;
      await tapVisible(tester, find.text('Descargar última copia'));
      await tester.pumpAndSettle();
      expect(find.text('Sin copia en Drive'), findsOneWidget);
      expect(find.textContaining('Remoto desconocido'), findsNothing);
      expect(download.applied, 0);
      await tapVisible(tester, find.text('Volver a Gestión'));
      await tester.pumpAndSettle();
      expect(upload.calls, 0);
      expect(download.calls, 1);
    },
  );

  testWidgets(
    'teclado Windows: Tab, Mayús Tab, Intro, Escape y retorno de foco',
    (tester) async {
      final upload = Uploader();
      final download = Downloader();
      final drive = controller(upload, download);
      await open(tester, drive);
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Descargar última copia'),
      );
      button.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('se perderán los cambios'), findsOneWidget);
      expect(find.text('Versión remota: 7'), findsOneWidget);
      final cancel = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Cancelar'),
      );
      expect(Focus.of(tester.element(find.text('Cancelar'))).hasFocus, true);
      expect(cancel.autofocus, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        Focus.of(tester.element(find.text('Descargar y sustituir'))).hasFocus,
        true,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(Focus.of(tester.element(find.text('Cancelar'))).hasFocus, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(download.applied, 0);
      expect(button.focusNode!.hasFocus, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(download.applied, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('tacto Android: aviso, confirmación, resultado y respaldo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final upload = Uploader();
    final download = Downloader();
    final drive = controller(upload, download);
    await open(tester, drive);
    final target = find.widgetWithText(
      OutlinedButton,
      'Descargar última copia',
    );
    expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
    await tapVisible(tester, target);
    await tester.pumpAndSettle();
    expect(download.applied, 0);
    await tapVisible(tester, find.text('Descargar y sustituir'));
    await tester.pumpAndSettle();
    expect(download.applied, 1);
    expect(find.textContaining('Copia descargada.'), findsOneWidget);
    expect(find.textContaining('respaldo-sintetico'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cancelación bloquea doble acción y salida hasta resultado seguro',
    (tester) async {
      final upload = Uploader()..wait = Completer<void>();
      final download = Downloader();
      final drive = controller(upload, download);
      await open(tester, drive);
      await tapVisible(tester, find.text('Subir copia'));
      await tester.pump();
      expect(drive.busy, true);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Descargar última copia'),
            )
            .onPressed,
        isNull,
      );
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      await nav.maybePop();
      await tester.pump();
      expect(find.text('Copia en Drive'), findsOneWidget);
      await tester.ensureVisible(find.text('Cancelar operación'));
      await tapVisible(tester, find.text('Cancelar operación'));
      await tester.pumpAndSettle();
      expect(upload.calls, 1);
      expect(download.calls, 0);
      expect(find.textContaining('Subida cancelada'), findsOneWidget);
    },
  );

  for (final status in [
    DriveUploadStatus.divergence,
    DriveUploadStatus.comparisonRequired,
    DriveUploadStatus.reconciliationRequired,
    DriveUploadStatus.failed,
  ]) {
    testWidgets('subida $status no muestra éxito', (tester) async {
      final upload = Uploader()..status = status;
      final drive = controller(upload, Downloader());
      await open(tester, drive);
      await tapVisible(tester, find.text('Subir copia'));
      await tester.pumpAndSettle();
      expect(drive.error, true);
      expect(find.textContaining('Copia subida'), findsNothing);
      if (status == DriveUploadStatus.divergence) {
        expect(find.text('Conservar datos locales'), findsOneWidget);
      }
      if (status == DriveUploadStatus.comparisonRequired) {
        expect(find.text('Copias divergentes'), findsNothing);
        expect(find.textContaining('pendiente de contrastar'), findsOneWidget);
      }
      if (status == DriveUploadStatus.reconciliationRequired) {
        expect(
          find.textContaining('No se pudo confirmar la subida'),
          findsOneWidget,
        );
      }
    });
  }

  testWidgets(
    'sin cambios locales continúa tras el clic sin advertencia de pérdida',
    (tester) async {
      final download = Downloader()..localStatus = SyncLocalStatus.clean;
      final drive = controller(Uploader(), download);
      await open(tester, drive);
      await tapVisible(tester, find.text('Descargar última copia'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(download.applied, 1);
      expect(find.textContaining('Versión 7'), findsOneWidget);
    },
  );

  for (final rejection in [
    DriveDownloadStatus.invalidImage,
    DriveDownloadStatus.remoteUnavailable,
    DriveDownloadStatus.reconciliationRequired,
  ]) {
    testWidgets('descarga $rejection conserva datos y muestra error', (
      tester,
    ) async {
      final download = Downloader()..rejection = rejection;
      final drive = controller(Uploader(), download);
      await open(tester, drive);
      await tapVisible(tester, find.text('Descargar última copia'));
      await tester.pumpAndSettle();
      expect(download.applied, 0);
      expect(drive.error, true);
      expect(find.textContaining('Copia descargada.'), findsNothing);
      expect(find.textContaining('No se descargó la copia'), findsOneWidget);
    });
  }
  testWidgets(
    'progreso de recuperación segura permite cancelar y bloquea navegación',
    (tester) async {
      final download = Downloader()..wait = Completer<void>();
      final drive = controller(Uploader(), download);
      await open(tester, drive);
      await tapVisible(tester, find.text('Descargar última copia'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Descargar y sustituir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text('Creando respaldo y sustituyendo/abriendo la base'),
        findsOneWidget,
      );
      expect(drive.busy, true);
      await tester.ensureVisible(find.text('Cancelar operación'));
      await tapVisible(tester, find.text('Cancelar operación'));
      await tester.pumpAndSettle();
      expect(download.applied, 0);
      expect(drive.error, false);
    },
  );
  testWidgets(
    'recuperación requerida mantiene bloqueo y muestra resultado sin éxito',
    (tester) async {
      final download = Downloader()
        ..status = DriveDownloadApplicationStatus.recoveryRequired;
      final drive = controller(Uploader(), download);
      await open(tester, drive);
      await tapVisible(tester, find.text('Descargar última copia'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Descargar y sustituir'));
      await tester.pumpAndSettle();
      expect(drive.recoveryBlocked, true);
      expect(drive.error, true);
      expect(find.text('Abrir Copias locales'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Subir copia'),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('Copia descargada.'), findsNothing);
    },
  );

  for (final size in [
    const Size(320, 800),
    const Size(360, 800),
    const Size(412, 915),
    const Size(839, 800),
    const Size(840, 800),
    const Size(1024, 768),
    const Size(1200, 900),
    const Size(1440, 900),
  ]) {
    testWidgets('layout $size con texto 200 %', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final drive = controller(Uploader(), Downloader());
      await open(tester, drive);
      await tester.ensureVisible(find.text('Descargar última copia'));
      expect(tester.takeException(), isNull);
      await tapVisible(tester, find.text('Descargar última copia'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Cancelar'));
      await tapVisible(tester, find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
