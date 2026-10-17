import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/local_backup_session.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/features/synchronization/export_saving.dart';
import 'package:myautofinance/features/synchronization/presentation/export_controller.dart';
import 'package:myautofinance/features/synchronization/presentation/export_screen.dart';

import '../test/support/app_navigation.dart';
import '../test/support/recovery_reference.dart';

// Prueba interactiva T06: solo instalación temporal y casos sintéticos EP-001.
// El operador cancela el primer selector y guarda los dos siguientes.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Gestión exporta CSV de meses y copia total con selector real', (
    tester,
  ) async {
    final support = await getApplicationSupportDirectory();
    final parent = await Directory('${support.path}/synthetic-export-224')
        .create(recursive: true);
    final temp = await parent.createTemp('run-');
    final fixture = Directory(await temp.resolveSymbolicLinks());
    final session = LocalBackupSession(supportDirectory: () async => fixture);
    tester.testTextInput.register();
    try {
      expect(await session.open(), isTrue);
      final db = await session.store.open();
      await seedRecoveryReference(db);
      final before = await db.readState();
      await tester.pumpWidget(AutofinanceApp(localSession: session));
      await tester.pumpAndSettle();
      await selectAppDestination(tester, SessionDestination.management);
      Future<void> tap(String label) async {
        final finder = find.text(label).last;
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await tap('Exportar datos');
      await tap('Rango de meses');
      await tester.enterText(
        find.byKey(const ValueKey('export-from')),
        '2026-01',
      );
      await tester.enterText(
        find.byKey(const ValueKey('export-through')),
        '2026-01',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final outcomes = <Map<String, Object?>>[];
      Future<ExportController> save(String label, String button) async {
        final c = tester
            .widget<ExportScreen>(find.byType(ExportScreen))
            .controller;
        final finder = find.text(button).last;
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        // ignore: avoid_print
        print('MA-TSK-224: $label');
        await tester.runAsync(() async {
          await tester.tap(finder);
          final deadline = DateTime.now().add(const Duration(minutes: 5));
          while (c.busy && DateTime.now().isBefore(deadline)) {
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        });
        await tester.pumpAndSettle();
        expect(c.busy, isFalse);
        outcomes.add({
          'stage': label,
          'result': c.result.runtimeType.toString(),
          'location': c.result is ExportSaved
              ? (c.result as ExportSaved).location
              : null,
          'displayName': c.result is ExportSaved
              ? (c.result as ExportSaved).displayName
              : null,
          'scope': c.exportedScope,
          'revision': c.capturedState?.revision,
          'createdAtUtc': c.capturedAt?.toIso8601String(),
        });
        return c;
      }

      final cancelled = await save('CANCELAR selector CSV', 'Guardar ZIP');
      expect(cancelled.result, isA<ExportSaveCancelled>());
      expect(cancelled.from, '2026-01');
      final csv = await save(
        'GUARDAR CSV enero sintético',
        'Reintentar guardado',
      );
      expect(csv.result, isA<ExportSaved>());
      expect(csv.capturedState!.revision, before.revision);
      expect(
        find.textContaining('Contenido verificado: siete CSV'),
        findsOneWidget,
      );
      await tap('Volver al origen');
      await tap('Exportar copia completa');
      final copy = await save(
        'GUARDAR copia completa sintética',
        'Guardar ZIP',
      );
      expect(copy.result, isA<ExportSaved>());
      expect(copy.exportedScope, 'Todo el histórico');
      expect(copy.capturedState!.revision, before.revision);
      final after = await db.readState();
      expect(after.datasetId, before.datasetId);
      expect(after.revision, before.revision);
      await tap('Consultar guía');
      await tap('Volver al recorrido');
      await tap('Volver al origen');
      expect(find.byType(ExportScreen), findsNothing);
      binding.reportData = {
        'platform': Platform.operatingSystem,
        'syntheticDataOnly': true,
        'revisionUnchanged': true,
        'outcomes': outcomes,
      };
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    } finally {
      tester.testTextInput.unregister();
      await session.store.close();
      session.controller.dispose();
      await fixture.delete(recursive: true);
    }
  });
}
