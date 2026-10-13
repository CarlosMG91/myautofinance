import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:myautofinance/app/csv_import_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/import_factory.dart';
import 'package:myautofinance/app/regional.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/importing/presentation/import_controller.dart';
import 'package:myautofinance/features/importing/presentation/import_review_screen.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Lee únicamente el CSV sintético creado por este test. IMPORT_NATIVE_SELECTOR
// permite revisar el diálogo del sistema; el valor por defecto sustituye solo
// la selección del documento, conservando lectura, parser y SQLite reales.
class _FixtureSelector implements LocalCsvSelector {
  const _FixtureSelector(this.file);
  final File file;
  @override
  Future<LocalCsvSelection> select() async => LocalCsvSelected(
    name: p.basename(file.path),
    bytes: await file.readAsBytes(),
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'CSV sintético en UI nativa: revisión, cancelación, lote y repetición',
    (tester) async {
      final support = await getApplicationSupportDirectory();
      final root = await Directory(
        p.join(support.path, 'import-redesign-tests'),
      ).create(recursive: true);
      final temporary = await root.createTemp('synthetic-214-');
      final file = await File(p.join(temporary.path, 'actividad-sintetica.csv'))
          .writeAsString(
            'fecha;concepto;importe_eur;tipo;categoria;subcategoria;subsubcategoria;cuenta_origen;discrecionalidad\n'
            '2026-01-03;Café;-2.50;REAL;;;;Cuenta sintética;Discrecional\n'
            '2026-01-01;Presupuesto;40.00;PRESUPUESTO;Ocio;;;;\n',
          );
      // No se abre la instalación personal ni se compone Drive.
      final db = LocalDatabase(
        NativeDatabase.memory(setup: configureConnection),
      );
      final services = createImportServices(db);
      final controller = createCsvImportController(
        () async => services,
        selector: const bool.fromEnvironment('IMPORT_NATIVE_SELECTOR')
            ? null
            : _FixtureSelector(file),
      );
      final captureKey = GlobalKey();
      final captures = <String, String>{};
      binding.reportData = {'importCaptures': captures};
      Future<void> settle() async {
        for (var i = 0; i < 1200; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 100));
          if (!controller.busy) {
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            return;
          }
        }
        fail('La selección o lectura no terminó.');
      }

      Future<void> press(String text, {bool wait = true}) async {
        await tester.ensureVisible(find.text(text).last);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.text(text).last);
        if (wait) await settle();
      }

      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final captureDirectory = await Directory(p.join(root.path, 'capturas'))
            .create(recursive: true);
        final destination = p.join(
          captureDirectory.path,
          '${Platform.operatingSystem}-$name.png',
        );
        await File(destination).writeAsBytes(bytes!.buffer.asUint8List());
        captures['native-${Platform.operatingSystem}-$name.png'] = base64Encode(
          bytes.buffer.asUint8List(),
        );
        image.dispose();
        debugPrint('IMPORT_CAPTURE: $destination');
      }

      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: AfTheme.light(),
            locale: AppRegional.locale,
            supportedLocales: AppRegional.supportedLocales,
            localizationsDelegates: AppRegional.delegates,
            home: RepaintBoundary(
              key: captureKey,
              child: ImportReviewScreen(
                controller: controller,
                onReturn: () {},
                onHistory: () {},
                onBatch: (_) {},
                onPeriod: (_, _) {},
              ),
            ),
          ),
        );
        await settle();
        await capture('seleccion');
        debugPrint('IMPORT_FIXTURE: ${file.path}');
        await press('Seleccionar CSV');
        expect(
          controller.session?.file.originalName,
          'actividad-sintetica.csv',
        );
        expect(controller.canConfirm, isFalse);
        await controller.bindAccount(
          ImportAccountReference.named('Cuenta sintética'),
          plan: ImportNewAccount(
            name: 'Cuenta sintética',
            activeFrom: Month(2026, 1),
            liquidity: Liquidity.liquid,
          ),
        );
        await controller.bindCategory(
          ImportCategoryReference(['Ocio']),
          plan: const ImportNewCategory(name: 'Ocio', isIncome: false),
        );
        await settle();
        await tester.ensureVisible(find.text('REAL'));
        await capture('resumen');
        await press('Confirmar lote completo');
        await press('Seguir revisando');
        expect((await services.history.listBatches()).items, isEmpty);
        await press('Confirmar lote completo');
        await press('Importar todo');
        expect(controller.phase, ImportPhase.imported);
        expect((controller.result as ImportConfirmed).batch.movementCount, 1);
        expect((controller.result as ImportConfirmed).batch.budgetCount, 1);
        await tester.ensureVisible(find.text('Importación completada'));
        await capture('resultado');
        final revision = (await db.readState()).revision;
        debugPrint('IMPORT_FIXTURE: ${file.path}');
        await press('Volver a cargar CSV', wait: false);
        // El selector nativo mantiene busy mientras el diálogo está abierto.
        for (
          var i = 0;
          i < 1200 && find.text('Descartar y cargar').evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        await press('Descartar y cargar');
        expect(controller.phase, ImportPhase.alreadyImported);
        expect((await db.readState()).revision, revision);
        expect((await services.history.listBatches()).items.length, 1);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await db.close();
        await temporary.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
