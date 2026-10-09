import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/features/synchronization/domain/drive_download.dart';
import 'package:myautofinance/features/synchronization/domain/drive_download_application.dart';
import 'package:myautofinance/features/synchronization/domain/drive_metadata.dart';
import 'package:myautofinance/features/synchronization/domain/drive_transfer.dart';
import 'package:myautofinance/features/synchronization/domain/drive_upload.dart';
import 'package:myautofinance/features/synchronization/domain/installation_sync_state.dart';
import 'package:myautofinance/features/synchronization/domain/local_restore.dart';
import 'package:myautofinance/features/synchronization/presentation/drive_controller.dart';

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
      restore: status == DriveDownloadApplicationStatus.downloaded
          ? const LocalRestoreResult(
              LocalRestoreStatus.restored,
              previousBackupId: 'respaldo-sintetico',
            )
          : null,
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
  await tester.tap(find.text('Gestión'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Copia en Drive'));
  await tester.pumpAndSettle();
}

void main() {
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
          await tester.tap(find.text('Descargar última copia'));
          await tester.pumpAndSettle();
          await capture('confirmacion');
          await tester.ensureVisible(find.text('Cancelar'));
          await tester.tap(find.text('Cancelar'));
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
      await tester.tap(find.text('Descargar última copia'));
      await tester.pumpAndSettle();
      expect(find.text('Sin copia en Drive'), findsOneWidget);
      expect(find.textContaining('Remoto desconocido'), findsNothing);
      expect(download.applied, 0);
      await tester.tap(find.textContaining('Volver a Estado del mes'));
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
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(download.applied, 0);
    await tester.tap(find.text('Descargar y sustituir'));
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
      await tester.tap(find.text('Subir copia'));
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
      await tester.tap(find.text('Cancelar operación'));
      await tester.pumpAndSettle();
      expect(upload.calls, 1);
      expect(download.calls, 0);
      expect(find.textContaining('Subida cancelada'), findsOneWidget);
    },
  );

  for (final status in [
    DriveUploadStatus.divergence,
    DriveUploadStatus.reconciliationRequired,
    DriveUploadStatus.failed,
  ]) {
    testWidgets('subida $status no muestra éxito', (tester) async {
      final upload = Uploader()..status = status;
      final drive = controller(upload, Downloader());
      await open(tester, drive);
      await tester.tap(find.text('Subir copia'));
      await tester.pumpAndSettle();
      expect(drive.error, true);
      expect(find.textContaining('Copia subida'), findsNothing);
      if (status == DriveUploadStatus.divergence) {
        expect(find.text('Conservar datos locales'), findsOneWidget);
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
      await tester.tap(find.text('Descargar última copia'));
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
      await tester.tap(find.text('Descargar última copia'));
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
      await tester.tap(find.text('Descargar última copia'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Descargar y sustituir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text('Creando respaldo y sustituyendo/abriendo la base'),
        findsOneWidget,
      );
      expect(drive.busy, true);
      await tester.ensureVisible(find.text('Cancelar operación'));
      await tester.tap(find.text('Cancelar operación'));
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
      await tester.tap(find.text('Descargar última copia'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Descargar y sustituir'));
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
      await tester.tap(find.text('Descargar última copia'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Cancelar'));
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
