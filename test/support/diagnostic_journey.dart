import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/local_backup_session.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/diagnostics/presentation/diagnostic_screen.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

import 'recovery_reference.dart';

Future<Map<String, Object?>> diagnosticDatabaseImage(
  LocalDatabase db,
) async => {
  for (final table
      in await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
          )
          .get())
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

/// Recorrido compartido de widgets y runners nativos; solo base privada sintética.
Future<void> diagnosticJourney(
  WidgetTester tester,
  Directory directory, {
  GlobalKey? captureKey,
  Future<void> Function(String)? capture,
}) async {
  final local = LocalBackupSession(supportDirectory: () async => directory);
  final navigation = NavigationSession(
    initialContext: NavigationContext(
      destination: SessionDestination.analysis,
      period: NavigationPeriod(2026, 1),
    ),
  );
  Future<T> io<T>(Future<T> Function() operation) async =>
      (await tester.runAsync(operation)) as T;
  Future<void> settle() async {
    for (var i = 0; i < 250; i++) {
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump(const Duration(milliseconds: 50));
      final screen = find.byType(DiagnosticScreen);
      final waiting =
          screen.evaluate().isNotEmpty &&
          (tester.widget<DiagnosticScreen>(screen.first).controller.busy ||
              tester
                  .widget<DiagnosticScreen>(screen.first)
                  .controller
                  .checking);
      if (i >= 12 && !waiting) break;
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> press(String text) async {
    final finder = find.text(text).first;
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await settle();
  }

  Future<Map<String, Object?>> image() =>
      io(() async => diagnosticDatabaseImage(await local.store.open()));
  try {
    debugPrint('MA-TSK-201 synthetic: opening');
    expect(await io(local.open), isTrue);
    debugPrint('MA-TSK-201 synthetic: seeding');
    final db = await io(local.store.open);
    final account = await io(() => seedRecoveryReference(db));
    await io(
      () => SqliteImportBatchRepository(db).create(
        sha256: 'd' * 64,
        source: ImportSource.historicalCsv,
        originalName: 'synthetic-diagnostic.csv',
        contractVersion: '1',
        movements: [
          ImportedMovement(
            2,
            MovementInput(
              accountId: account,
              valueDate: ValueDate(2026, 1, 7),
              concept: 'Pendiente sintético',
              amountCents: -1234,
            ),
          ),
        ],
        budgets: [],
      ),
    );
    final before = await image();
    debugPrint('MA-TSK-201 synthetic: mounting');
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: AutofinanceApp(
          localSession: local,
          navigationSession: navigation,
        ),
      ),
    );
    await settle();
    await press('Diagnóstico de coherencia');
    debugPrint('MA-TSK-201 synthetic: entered');
    expect(find.text('Ejecutar diagnóstico'), findsOneWidget);
    expect(find.text('Revisión con hallazgos'), findsNothing);
    await capture?.call('inicio');
    await press('Ejecutar diagnóstico');
    debugPrint('MA-TSK-201 synthetic: executed');
    expect(find.text('Pendientes: 1'), findsOneWidget);
    expect(find.text('9 de 9 reglas ejecutadas'), findsOneWidget);
    await capture?.call('resultado');
    await press('Movimiento sin categoría');
    expect(find.textContaining('−12,34 €'), findsNWidgets(2));
    await capture?.call('detalle');
    // Etiqueta contiene UUID: seleccionarla por el contrato visible del botón.
    final pending = find.byWidgetPredicate(
      (w) => w is AfAction && w.label.startsWith('Abrir bandeja ·'),
    );
    expect(pending, findsOneWidget);
    await tester.ensureVisible(pending);
    await tester.tap(pending);
    await settle();
    expect(find.text('Bandeja de categorización'), findsOneWidget);
    await press('Volver a Diagnóstico');
    expect(find.textContaining('Resultado obsoleto.'), findsNothing);
    expect(navigation.period, NavigationPeriod(2026, 1));
    expect(await image(), before);
    // Una restauración real con idénticos UUID/revisión invalida por generación.
    await io(local.controller.create);
    expect(local.controller.error, isNull);
    final copy = local.controller.listing!.entries.single.backupId;
    await io(() => local.controller.restore(copy, confirmed: true));
    expect(local.controller.restoreResult!.status, LocalRestoreStatus.restored);
    await settle();
    expect(find.textContaining('Resultado obsoleto.'), findsOneWidget);
    await capture?.call('obsoleto');
    await press('Repetir diagnóstico');
    expect(find.textContaining('Resultado obsoleto.'), findsNothing);
    expect(await image(), before);
    await io(() => navigation.selectPeriod(NavigationPeriod(2026, 2)));
    await settle();
    expect(find.textContaining('Resultado obsoleto.'), findsOneWidget);
    await press('Repetir diagnóstico');
    expect(find.text('Foto ausente'), findsOneWidget);
    await press('Foto ausente');
    await capture?.call('foto-pendiente');
    await press('Completar foto · 2026-02-01');
    await tester.binding.handlePopRoute();
    await settle();
    expect(navigation.period, NavigationPeriod(2026, 2));
    expect(find.textContaining('Resultado obsoleto.'), findsNothing);
    expect(await image(), before);
    // El informe desaparece al cerrar la visita/app, sin historial.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      AutofinanceApp(localSession: local, navigationSession: navigation),
    );
    await settle();
    expect(find.text('Ejecutar diagnóstico'), findsOneWidget);
    expect(find.text('9 de 9 reglas ejecutadas'), findsNothing);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await io(local.store.close);
    local.controller.dispose();
    navigation.dispose();
    await local.categoryInvalidation.close();
  }
}
