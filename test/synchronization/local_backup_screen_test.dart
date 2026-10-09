import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/navigation/app_routes.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';
import 'package:myautofinance/features/synchronization/presentation/local_backup_controller.dart';

const _id = '11111111-1111-4111-8111-111111111111';

class _Catalog implements LocalBackupCatalog {
  List<LocalBackupCatalogEntry> entries = [_entry()];
  LocalBackupCatalogStatus status = LocalBackupCatalogStatus.ready;
  Object? failure;
  List<LocalBackupCatalogIncident> incidents = [];
  @override
  Future<LocalBackupCatalogListing> read() async {
    if (failure case final failure?) throw failure;
    return LocalBackupCatalogListing(
      status: status,
      entries: entries,
      incidents: incidents,
      pruningAllowed: true,
    );
  }

  @override
  Future<LocalBackupMaintenanceResult> deleteExplicitly(
    String backupId, {
    Set<String> protectedBackupIds = const {},
  }) async {
    entries = [];
    return LocalBackupMaintenanceResult(
      deletedBackupIds: [backupId],
      incidents: [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

LocalBackupCatalogEntry _entry({bool corrupt = false}) =>
    LocalBackupCatalogEntry(
      backupId: _id,
      createdAtUtc: DateTime.utc(2026, 10, 2, 9, 30),
      creationOrder: 1,
      origin: LocalBackupOrigin.manual,
      sizeBytes: 1024,
      availability: corrupt
          ? LocalBackupAvailability.incomplete
          : LocalBackupAvailability.present,
      validation: corrupt
          ? LocalBackupValidationState.invalid
          : LocalBackupValidationState.valid,
      checkedAtUtc: DateTime.utc(2026, 10, 2, 9, 30),
      issue: null,
    );

class _Creator implements LocalBackupCreator {
  int calls = 0;
  @override
  Future<CreatedLocalBackup> createManual() async {
    calls++;
    throw const LocalBackupFailure(LocalBackupFailureCode.storageFailure);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Restorer implements LocalRestorer {
  int calls = 0;
  LocalRestoreResult result = const LocalRestoreResult(
    LocalRestoreStatus.restored,
    previousBackupId: _id,
  );
  Completer<LocalRestoreResult>? pending;
  @override
  Future<LocalRestoreResult> restore(
    String id, {
    required bool confirmed,
  }) async {
    expect(id, _id);
    expect(confirmed, isTrue);
    calls++;
    return pending?.future ?? result;
  }
}

void main() {
  late _Catalog catalog;
  late _Creator creator;
  late _Restorer restorer;
  late LocalBackupController controller;
  setUp(() {
    catalog = _Catalog();
    creator = _Creator();
    restorer = _Restorer();
    controller = LocalBackupController(
      catalog: catalog,
      creator: creator,
      restorer: restorer,
    );
  });
  tearDown(() => controller.dispose());

  Future<void> open(
    WidgetTester tester, {
    bool recovery = false,
    Size size = const Size(1024, 768),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    controller.activeAvailable = !recovery;
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('capture'),
        child: AutofinanceApp(localBackups: controller),
      ),
    );
    await tester.pumpAndSettle();
    if (!recovery) {
      final context = tester.element(find.text('Marcador técnico · /estado'));
      Navigator.of(context).pushNamed(AppRoutes.localBackups);
      await tester.pumpAndSettle();
    }
  }

  Future<void> detail(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Ver detalle').first);
    await tester.tap(find.text('Ver detalle').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Restaurar esta copia'));
    await tester.tap(find.text('Restaurar esta copia'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Cancelar y Esc conservan datos, no llaman al servicio y devuelven foco',
    (tester) async {
      await open(tester);
      await detail(tester);
      final confirm = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Restaurar copia'),
      );
      expect(confirm.onPressed, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.ancestor(
          of: find.byElementPredicate(
            (element) => element == FocusManager.instance.primaryFocus?.context,
          ),
          matching: find.widgetWithText(FilledButton, 'Restaurar esta copia'),
        ),
        findsOneWidget,
      );
      expect(restorer.calls, 0);
      expect(creator.calls, 0);
      expect(controller.restoreResult, isNull);
      await tester.tap(find.text('Restaurar esta copia'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(restorer.calls, 0);
      expect(controller.activeAvailable, isTrue);
    },
  );

  testWidgets(
    'Confirmación explícita, bloqueo de Atrás y éxito confirmado con respaldo',
    (tester) async {
      restorer.pending = Completer<LocalRestoreResult>();
      await open(tester);
      await detail(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('Restaurar copia'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(restorer.calls, 1);
      expect(controller.busy, isTrue);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('Restauración completada'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(controller.busy, isTrue);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      restorer.pending!.complete(restorer.result);
      await tester.pumpAndSettle();
      expect(find.textContaining('Restauración completada'), findsOneWidget);
      expect(find.text('Ver copia anterior'), findsOneWidget);
      expect(
        find.textContaining('Contraste con Drive pendiente'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Arranque fallido ofrece catálogo y restaura sin abrir rutas de datos',
    (tester) async {
      await open(tester, recovery: true);
      expect(
        find.textContaining('No se puede abrir la base activa'),
        findsOneWidget,
      );
      expect(find.text('Autofinance · Base técnica'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Crear copia'),
            )
            .onPressed,
        isNull,
      );
      await detail(tester);
      expect(find.textContaining('Se conservarán aislados'), findsOneWidget);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('Restaurar copia'));
      await tester.pumpAndSettle();
      expect(controller.activeAvailable, isTrue);
      expect(restorer.calls, 1);
    },
  );

  testWidgets(
    'Vacío, catálogo inaccesible y copia corrupta tienen estados distintos',
    (tester) async {
      catalog.entries = [];
      await open(tester, recovery: true);
      expect(find.text('Todavía no hay copias locales'), findsOneWidget);
      catalog.status = LocalBackupCatalogStatus.unavailable;
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(find.text('Todavía no hay copias locales'), findsNothing);
      expect(
        find.textContaining('Esto no significa que no haya copias'),
        findsOneWidget,
      );
      catalog.status = LocalBackupCatalogStatus.ready;
      catalog.entries = [_entry(corrupt: true)];
      await controller.refresh();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Ver detalle'));
      await tester.tap(find.text('Ver detalle'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Esta copia no se puede restaurar'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Restaurar esta copia'),
            )
            .onPressed,
        isNull,
      );
      expect(restorer.calls, 0);
    },
  );

  testWidgets('Error de almacenamiento permite reintentar sin anunciar éxito', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Crear copia'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Crear copia').last);
    await tester.pumpAndSettle();
    expect(creator.calls, 1);
    expect(find.textContaining('espacio libre'), findsOneWidget);
    expect(find.textContaining('Copia manual creada'), findsNothing);
    expect(controller.activeAvailable, isTrue);
  });

  if (const bool.fromEnvironment('CAPTURE_BACKUP_UI')) {
    for (final size in [
      const Size(1440, 900),
      const Size(412, 915),
      const Size(320, 800),
    ]) {
      testWidgets('Captura visual sintética $size', (tester) async {
        debugDefaultTargetPlatformOverride = size.width >= 840
            ? TargetPlatform.windows
            : TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final font = FontLoader(size.width >= 840 ? 'Segoe UI' : 'Roboto');
        await tester.runAsync(() async {
          final bytes = await File(
            size.width >= 840 ? 'C:/Windows/Fonts/segoeui.ttf' : '.tools/flutter/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
          ).readAsBytes();
          font.addFont(Future.value(ByteData.sublistView(bytes)));
          await font.load();
        });
        await open(tester, size: size, scale: size.width == 320 ? 2 : 1);
        Future<void> capture(String name) async {
          await tester.runAsync(() async {
            final render = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('capture')),
            );
            final picture = await render.toImage();
            final bytes = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('.tools/ma-tsk-058-${size.width.toInt()}-$name.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            picture.dispose();
          });
        }

        await capture('catalogo');
        await detail(tester);
        await capture('confirmacion');
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }

  for (final size in [
    const Size(320, 800),
    const Size(360, 800),
    const Size(412, 915),
    const Size(839, 800),
    const Size(840, 800),
    const Size(1024, 768),
    const Size(1199, 900),
    const Size(1200, 900),
    const Size(1440, 900),
  ]) {
    testWidgets('Tabla/tarjetas operables en $size, texto 200 %', (
      tester,
    ) async {
      await open(tester, size: size, scale: 2);
      expect(
        find.byType(Table),
        size.width >= 840 ? findsOneWidget : findsNothing,
      );
      await tester.ensureVisible(find.text('Ver detalle').first);
      await tester.tap(find.text('Ver detalle').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Restaurar esta copia'));
      await tester.tap(find.text('Restaurar esta copia'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Cancelar'));
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(restorer.calls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Gestión desde cada destino vuelve al mismo origen', (
    tester,
  ) async {
    await tester.pumpWidget(AutofinanceApp(localBackups: controller));
    await tester.pumpAndSettle();
    for (final destination in AppRoutes.destinations) {
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed(destination.path);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gestión'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copias locales'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Volver a ${destination.label}'));
      await tester.pumpAndSettle();
      expect(
        find.text('Marcador técnico · ${destination.path}'),
        findsOneWidget,
      );
    }
  });

  testWidgets('Retorno conserva la ruta y el periodo de origen', (
    tester,
  ) async {
    await tester.pumpWidget(AutofinanceApp(localBackups: controller));
    await tester.pumpAndSettle();
    const route = '${AppRoutes.monthlyStatus}?a=2026&m=02';
    tester.state<NavigatorState>(find.byType(Navigator)).pushNamed(route);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gestión'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copias locales'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Volver a Estado del mes, febrero de 2026'));
    await tester.pumpAndSettle();
    expect(
      ModalRoute.of(tester.element(find.text('Estado del mes')))!.settings.name,
      route,
    );
  });

  test('Catálogo perdido no conserva una lista antigua; diario pendiente bloquea datos', () async {
    await controller.refresh();
    expect(controller.listing!.entries, hasLength(1));
    catalog.failure = StateError('detalle privado');
    await controller.refresh();
    expect(controller.listing, isNull);
    expect(controller.error, isNot(contains('detalle privado')));
    catalog.failure = null;
    catalog.incidents = [
      const LocalBackupCatalogIncident(
        LocalBackupCatalogIssue.unresolvedRestore,
      ),
    ];
    await controller.refresh();
    expect(controller.activeAvailable, isFalse);
    expect(controller.recoveryBlocked, isTrue);
    await controller.create();
    await controller.restore(_id, confirmed: true);
    expect(creator.calls, 0);
    expect(restorer.calls, 0);
  });

  test(
    'Rechazo tipado, rollback y recuperación pendiente controlan el acceso',
    () async {
      restorer.result = const LocalRestoreResult(
        LocalRestoreStatus.rejected,
        candidateIssue: LocalRestoreCandidateIssue.hashMismatch,
      );
      await controller.restore(_id, confirmed: true);
      expect(controller.error, contains('ha cambiado'));
      expect(controller.activeAvailable, isTrue);
      restorer.result = const LocalRestoreResult(LocalRestoreStatus.rolledBack);
      await controller.restore(_id, confirmed: true);
      expect(controller.error, contains('base anterior'));
      restorer.result = const LocalRestoreResult(
        LocalRestoreStatus.recoveryRequired,
      );
      await controller.restore(_id, confirmed: true);
      expect(controller.activeAvailable, isFalse);
      expect(controller.recoveryBlocked, isTrue);
      final calls = restorer.calls;
      await controller.restore(_id, confirmed: true);
      await controller.create();
      expect(restorer.calls, calls);
      expect(creator.calls, 0);
    },
  );
}
