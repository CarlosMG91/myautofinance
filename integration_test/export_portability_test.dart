import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/local_backup_factory.dart';
import 'package:myautofinance/app/local_backup_session.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_wealth_repository.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:myautofinance/features/synchronization/export_saving.dart';
import 'package:myautofinance/features/synchronization/presentation/export_screen.dart';

import '../test/support/app_navigation.dart';
import '../test/support/recovery_reference.dart';

// T08 interactivo. El operador cancela el primer selector y guarda los ocho
// ZIP siguientes con el nombre de etapa impreso en el log. Sin dobles nativos.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('EP-027 portabilidad nativa de referencia y variantes', (
    tester,
  ) async {
    final support = await getApplicationSupportDirectory();
    final parent = await Directory('${support.path}/synthetic-export-226')
        .create(recursive: true);
    final temporary = await parent.createTemp('run-');
    final fixture = Directory(await temporary.resolveSymbolicLinks());
    final session = LocalBackupSession(supportDirectory: () async => fixture);
    tester.testTextInput.register();
    try {
      expect(await session.open(), isTrue);
      final db = await session.store.open();
      await seedRecoveryReference(db);
      await createLocalBackupCreator(
        store: session.store,
        supportDirectory: () async => fixture,
      ).createManual();
      final private = Directory('${fixture.path}/sqlite/local-backups');
      Future<Map<String, String>> fingerprints() async => {
        await for (final f in private.list(recursive: true, followLinks: false))
          if (f is File)
            f.path: sha256.convert(await f.readAsBytes()).toString(),
      };
      final previousCopies = await fingerprints();
      final tableNames =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
                  )
                  .get())
              .map((r) => r.read<String>('name'))
              .toList();
      Future<Map<String, Object?>> capture() async => {
        for (final name in tableNames)
          name:
              (await db.customSelect('SELECT * FROM "$name" ORDER BY 1').get())
                  .map(
                    (row) => {
                      for (final cell in row.data.entries)
                        cell.key: cell.value is int
                            ? '${cell.value}'
                            : cell.value,
                    },
                  )
                  .toList(),
      };
      await tester.pumpWidget(AutofinanceApp(localSession: session));
      await tester.pumpAndSettle();
      await selectAppDestination(tester, SessionDestination.management);
      Future<void> tap(String label) async {
        final f = find.text(label).last;
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      final outcomes = <Map<String, Object?>>[];
      Future<void> export(
        String stage, {
        String? month,
        bool complete = false,
        bool cancel = false,
      }) async {
        await tap(complete ? 'Exportar copia completa' : 'Exportar datos');
        if (month != null) {
          await tap('Rango de meses');
          for (final key in ['export-from', 'export-through']) {
            await tester.enterText(find.byKey(ValueKey(key)), month);
          }
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
        }
        final before = await capture();
        final state = await db.readState();
        final c = tester
            .widget<ExportScreen>(find.byType(ExportScreen))
            .controller;
        final button = find.text('Guardar ZIP').last;
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        // ignore: avoid_print
        print('MA-TSK-226: $stage');
        await tester.runAsync(() async {
          await tester.tap(button);
          final deadline = DateTime.now().add(const Duration(minutes: 5));
          while (c.busy && DateTime.now().isBefore(deadline)) {
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        });
        await tester.pumpAndSettle();
        expect(c.busy, isFalse);
        expect(c.cleanupWarning, isNull);
        if (cancel) {
          expect(c.result, isA<ExportSaveCancelled>());
        } else {
          expect(c.result, isA<ExportSaved>());
          expect(c.capturedState!.datasetId, state.datasetId);
          expect(c.capturedState!.revision, state.revision);
        }
        expect(await capture(), before, reason: 'Exportar no escribe datos');
        expect(await fingerprints(), previousCopies);
        outcomes.add({
          'stage': stage,
          'month': month,
          'complete': complete,
          'result': c.result.runtimeType.toString(),
          'location': c.result is ExportSaved
              ? (c.result as ExportSaved).location
              : null,
          'displayName': c.result is ExportSaved
              ? (c.result as ExportSaved).displayName
              : null,
          'datasetId': state.datasetId,
          'revision': '${state.revision}',
          'capture': before,
        });
        if (stage == 'base-copy') {
          await tap('Consultar guía');
          await tap('Volver al recorrido');
        }
        // La cancelación conserva un borrador: confirmar salida desde el test.
        if (cancel) c.dirty = false;
        await tap('Volver al origen');
      }

      await export('cancel', month: '2026-01', cancel: true);
      await export('all');
      await export('january', month: '2026-01');
      await export('empty', month: '2025-12');
      await export('base-copy', complete: true);

      final accounts = SqliteAccountRepository(db);
      final catalog = await accounts.list();
      String id(String name) => catalog.singleWhere((a) => a.name == name).id;
      final wealth = SqliteWealthRepository(db);
      final feb = Month(2026, 2);
      await wealth.setValue(feb, id('Cuenta principal'), 620000);
      await wealth.setValue(feb, id('Deuda familiar'), 480000);
      await export('partial', month: '2026-02');
      await wealth.setValue(feb, id('Cuenta de ahorro'), 0);
      await wealth.setValue(feb, id('Cartera'), 1050000);
      await export('zero', month: '2026-02');
      await accounts.changeLiquidity(id('Cartera'), feb, Liquidity.liquid);
      const edgeText = 'Árbol; "Café"\nsegunda línea 🧪';
      // Variante separada: no altera las cifras base EP-001 ya exportadas.
      await db.customStatement(
        "UPDATE movements SET concept=?,discretion=?,amount_cents=? WHERE id=(SELECT id FROM movements WHERE value_date>='2026-02-01' ORDER BY id LIMIT 1)",
        [edgeText, ' Discrecional; "sí"\r\n漢字 ', 9223372036854775807],
      );
      await export('history');
      await export('variant-copy', complete: true);
      binding.reportData = {
        'ticket': 'MA-TSK-226',
        'platform': Platform.operatingSystem,
        'syntheticDataOnly': true,
        'privateCopiesUnchanged': true,
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
  }, timeout: const Timeout(Duration(minutes: 45)));
}
