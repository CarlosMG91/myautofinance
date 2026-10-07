import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/local_backup_session.dart';
import 'package:myautofinance/app/import_factory.dart';
import 'package:myautofinance/app/navigation/app_routes.dart';
import 'package:myautofinance/app/navigation/import_route.dart';
import 'package:myautofinance/core/config/app_config.dart';
import 'package:myautofinance/features/importing/data/sha256_import_fingerprint.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/importing/presentation/import_review_screen.dart';
import 'package:myautofinance/features/movements/movements.dart';

import 'synthetic_import_adapter.dart';
import 'import_reference_journey.dart';

/// Un mismo guion sobre widgets y Windows/Android, con SQLite real desechable.
/// No contiene un lector de archivos de usuario ni un servicio simulado.
Future<void> importLifecycleJourney(
  WidgetTester tester,
  Directory directory, {
  required bool desktop,
}) async {
  var installation = LocalBackupSession(
    supportDirectory: () async => directory,
  );
  Future<T> io<T>(Future<T> Function() action) async {
    Object? error;
    StackTrace? trace;
    final value = await tester.runAsync(() async {
      try {
        return await action().timeout(const Duration(seconds: 45));
      } catch (caught, stack) {
        error = caught;
        trace = stack;
        return null;
      }
    });
    if (error != null) Error.throwWithStackTrace(error!, trace!);
    return value as T;
  }

  Future<void> settle() async {
    for (var turn = 0; turn < 150; turn++) {
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump(const Duration(milliseconds: 50));
      if (turn >= 5 &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty &&
          find.text('Leyendo').evaluate().isEmpty &&
          find.text('Consultando SQLite…').evaluate().isEmpty) {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        return;
      }
    }
    fail('La operación de importación no terminó.');
  }

  Future<void> tap(Finder finder) async {
    await settle();
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(finder));
    await settle();
  }

  Future<void> press(String text) => tap(find.text(text).last);
  NavigatorState navigator() =>
      tester.state<NavigatorState>(find.byType(Navigator).first);
  Future<void> route(String path, {Object? arguments}) async {
    navigator().pushNamedAndRemoveUntil(
      path,
      (_) => false,
      arguments: arguments,
    );
    await settle();
  }

  Future<LocalDatabase> database() => installation.store.open();
  Future<Map<String, Object?>> image() => io(() async {
    final db = await database();
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        .get();
    return {
      for (final table in tables)
        table.read<String>(
          'name',
        ): (await db
                .customSelect(
                  'SELECT * FROM "${table.read<String>('name')}" ORDER BY rowid',
                )
                .get())
            .map((r) => r.data)
            .toList(),
      'local_mutation':
          (await db.customSelect('SELECT * FROM local_mutation').get())
              .map((r) => r.data)
              .toList(),
    };
  });

  Future<int> count(String table) => io(
    () async =>
        (await (await database())
                .customSelect('SELECT count(*) AS n FROM $table')
                .getSingle())
            .read<int>('n'),
  );
  Map<String, Object?> persisted(Map<String, Object?> value) =>
      Map.of(value)..remove('local_mutation');
  Future<void> mount() async {
    expect(await io(installation.open), isTrue);
    await tester.pumpWidget(
      AutofinanceApp(
        config: const AppConfig(environment: AppEnvironment.test),
        localSession: installation,
      ),
    );
    await settle();
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await io(installation.store.close);
    installation.controller.dispose();
    await io(installation.categoryInvalidation.close);
  }

  Map<String, Object?> real(
    int ordinal, {
    String concept = ' Café ',
    int cents = -1000,
  }) => {
    'kind': 'REAL',
    'ordinal': ordinal,
    'date': '2026-01-03',
    'concept': concept,
    'cents': cents,
    'account': 'Cuenta sintética',
    'fields': [
      {'name': 'concepto', 'value': concept},
      {'name': 'importe', 'value': '-10.00'},
      {'name': 'importe', 'value': 'texto original repetido'},
    ],
  };
  Map<String, Object?> budget(
    int ordinal, {
    String month = '2026-01',
    List<String> category = const ['Gastos'],
    int cents = 40000,
  }) => {
    'kind': 'PRESUPUESTO',
    'ordinal': ordinal,
    'month': month,
    'concept': 'Previsto',
    'cents': cents,
    'category': category,
  };
  ImportFile file(
    List<Map<String, Object?>> rows, {
    String name = 'sintetico.json',
    ImportSource source = ImportSource.historicalCsv,
  }) => ImportFile.fromBytes(
    bytes: utf8.encode(jsonEncode({'rows': rows})),
    fingerprint: const Sha256ImportFingerprint(),
    source: source,
    originalName: name,
  );
  Future<void> start(ImportFile input) => route(
    AppRoutes.importReview,
    arguments: ImportReviewLaunch(
      file: input,
      adapter: SyntheticImportAdapter(input.source),
      origin: '/real?a=2026&m=01',
    ),
  );
  final initial = file([
    real(2),
    real(3),
    real(4, concept: 'Abono pendiente', cents: 700),
    budget(5),
    budget(6, month: '2026-02', cents: 0),
  ]);
  Future<void> confirm() async {
    await press('Confirmar lote completo');
    await press('Importar todo');
  }

  try {
    debugPrint('EP-012: abrir instalación vacía');
    await mount();
    debugPrint('EP-012: capturar base vacía');
    final empty = await image();
    expect(await count('accounts'), 0);
    expect(await count('categories'), 0);
    await start(initial);
    debugPrint('EP-012: revisión inicial');
    expect(find.text('Confirmar lote completo'), findsOneWidget);
    final controller = tester
        .widget<ImportReviewScreen>(find.byType(ImportReviewScreen))
        .controller;
    expect(controller.canConfirm, isFalse);
    expect(find.byType(DataTable), desktop ? findsOneWidget : findsNothing);
    expect(find.textContaining('Sin clasificar'), findsWidgets);

    // Altas aprobadas desde la pantalla: no escriben ni al preparar ni cancelar.
    await press('Resolver cuenta: Cuenta sintética');
    await tap(find.byType(SwitchListTile));
    await press('Aplicar a la revisión');
    debugPrint('EP-012: cuenta preparada');
    await press('Resolver categoría: Gastos');
    await tap(find.byType(SwitchListTile));
    await tap(find.byType(DropdownButtonFormField<bool>));
    await press('No ingreso');
    await press('Aplicar a la revisión');
    debugPrint('EP-012: categoría preparada');
    expect(controller.canConfirm, isTrue);
    expect(await image(), empty);
    await press('Confirmar lote completo');
    await press('Seguir revisando');
    expect(await image(), empty);
    await confirm();
    debugPrint('EP-012: lote inicial confirmado');
    expect(find.text('Importado'), findsOneWidget);
    final batch = (controller.result as ImportConfirmed).batch;
    expect(batch.movementCount, 3);
    expect(batch.budgetCount, 2);
    final history = await io(
      () async => (await installation.imports()).history.listRows(batch.id),
    );
    expect(history.items.map((r) => r.sourceOrdinal), [2, 3, 4, 5, 6]);
    final duplicates = history.items.take(2).toList();
    expect(
      duplicates[0].currentMovement!.id,
      isNot(duplicates[1].currentMovement!.id),
    );
    expect(duplicates.map((r) => r.currentMovement!.data.amountCents), [
      -1000,
      -1000,
    ]);
    expect(
      history.items
          .take(3)
          .every((r) => r.currentMovement!.data.categoryId == null),
      isTrue,
    );
    expect(history.items[3].original!.amount.originalCents, 40000);
    expect(history.items[3].currentBudget!.data.amountCents, -40000);
    expect(history.items[4].currentBudget!.data.amountCents, 0);
    expect(history.items.first.original!.originalFields.map((f) => f.value), [
      ' Café ',
      '-10.00',
      'texto original repetido',
    ]);
    final committed = await image();
    expect((committed['database_state'] as List).single['revision'], 1);
    await press('Consultar lote y origen');
    expect(find.text('REAL: 3 · PRESUPUESTO: 2'), findsOneWidget);

    // Reiniciar composición/conexión; historial y datos idénticos en disco.
    await close();
    installation = LocalBackupSession(supportDirectory: () async => directory);
    await mount();
    expect(persisted(await image()), persisted(committed));
    await route(AppRoutes.importHistory);
    expect(find.text(initial.originalName), findsOneWidget);
    await press('Ver detalle del lote');
    expect(find.text('REAL: 3 · PRESUPUESTO: 2'), findsOneWidget);
    await press(desktop ? 'Ver origen 2' : 'Fila 2 · REAL');
    expect(find.text('Procedencia de fila'), findsOneWidget);

    // Corrección y borrado por repositorio real: originales nunca se reescriben.
    await io(() async {
      final repo = SqliteMovementRepository(await database());
      final current = duplicates.first.currentMovement!;
      await repo.edit(
        current.id,
        MovementInput(
          accountId: current.data.accountId,
          valueDate: current.data.valueDate,
          categoryId: current.data.categoryId,
          discretion: current.data.discretion,
          concept: 'Corregido',
          amountCents: -500,
        ),
      );
      await repo.delete(duplicates.last.currentMovement!.id);
    });
    await press('Recargar contexto');
    expect(find.textContaining('Corregido · −5,00 €'), findsOneWidget);
    await route('${AppRoutes.importRows}/${duplicates.last.id}');
    expect(find.textContaining('Registro borrado.'), findsOneWidget);
    expect(find.text('Abrir registro actual'), findsNothing);
    final edited = await image();
    await start(
      file([
        real(2),
        real(3),
        real(4, concept: 'Abono pendiente', cents: 700),
        budget(5),
        budget(6, month: '2026-02', cents: 0),
      ], name: 'renombrado.json'),
    );
    await confirm();
    expect(find.text('Ya importado'), findsOneWidget);
    expect(await image(), edited);

    // Errores de interpretación y conflicto jerárquico bloquean todo el archivo.
    for (final rows in <List<Map<String, Object?>>>[
      [],
      [
        real(2),
        {...real(3), 'date': '2026-02-30'},
      ],
      [
        real(2),
        {...budget(3), 'category': null},
      ],
      [real(2), real(2)],
      [
        real(2),
        budget(3),
        budget(4, category: ['Gastos', 'Hijo']),
      ],
    ]) {
      await start(file(rows));
      final c = tester
          .widget<ImportReviewScreen>(find.byType(ImportReviewScreen))
          .controller;
      expect(c.canConfirm, isFalse);
      expect(c.review!.issues, isNotEmpty);
      await io(c.confirm);
      expect(await image(), edited);
    }

    // Banco sin cuenta: selección obligatoria, REAL Sin clasificar permitido.
    final bank = file([
      {...real(2, concept: 'Cargo bancario'), 'account': null},
    ], source: ImportSource.bankXls);
    await start(bank);
    var c = tester
        .widget<ImportReviewScreen>(find.byType(ImportReviewScreen))
        .controller;
    expect(c.canConfirm, isFalse);
    final accountId = duplicates.first.currentMovement!.data.accountId;
    await press('Resolver cuenta: selección global');
    await tap(find.byType(DropdownButtonFormField<String>));
    await press('Cuenta sintética · $accountId');
    await press('Aplicar a la revisión');
    expect(c.canConfirm, isTrue);
    expect(await image(), edited);
    await confirm();
    expect(find.text('Importado'), findsOneWidget);

    // Un escritor independiente introduce un solapamiento DESPUÉS de revisar.
    await start(file([real(2, concept: 'Coincidencia concurrente')]));
    c = tester
        .widget<ImportReviewScreen>(find.byType(ImportReviewScreen))
        .controller;
    expect(c.canConfirm, isTrue);
    await io(() async {
      final second = LocalDatabase(
        NativeDatabase(
          File(installation.store.databasePath!),
          setup: configureConnection,
        ),
      );
      try {
        final otherFile = file([
          real(2, concept: ' COINCIDENCIA CONCURRENTE '),
        ]);
        final otherSession = ImportSession(
          file: otherFile,
          interpretation: await const SyntheticImportAdapter(
            ImportSource.historicalCsv,
          ).interpret(otherFile),
        );
        final otherReview = await createImportServices(second).previewer
            .preview(otherSession);
        expect(
          await SqliteImportBatchRepository(second)
              .confirm(ImportConfirmationRequest(review: otherReview)),
          isA<ImportConfirmed>(),
        );
      } finally {
        await second.close();
      }
    });
    final concurrent = await image();
    await confirm();
    expect(find.text('Error'), findsOneWidget);
    expect(c.failures, isNotEmpty);
    expect(c.canConfirm, isFalse);
    expect(await image(), concurrent);
    expect(find.byType(CheckboxListTile), findsOneWidget);
    await tap(find.byType(CheckboxListTile));
    await confirm();
    expect(find.text('Importado'), findsOneWidget);
    expect(await count('movements'), 5); // conserva la coincidencia y la nueva.

    // Fallo tardío tras referencias/registros: todo vuelve a la imagen anterior.
    await start(
      file([
        real(2, concept: 'Rollback'),
        real(3, concept: 'Rollback'),
        budget(4, category: ['Nueva']),
      ]),
    );
    c = tester
        .widget<ImportReviewScreen>(find.byType(ImportReviewScreen))
        .controller;
    await press('Resolver categoría: Nueva');
    await tap(find.byType(SwitchListTile));
    await tap(find.byType(DropdownButtonFormField<bool>));
    await press('No ingreso');
    await press('Aplicar a la revisión');
    await io(
      () async => (await database()).customStatement(
        "CREATE TEMP TRIGGER injected_114 BEFORE INSERT ON import_batch_metadata BEGIN SELECT RAISE(ABORT,'synthetic-114'); END",
      ),
    );
    final beforeFailure = await image();
    await confirm();
    expect(find.text('Error'), findsOneWidget);
    expect(c.hasSession, isTrue);
    expect(await image(), beforeFailure);
    await io(
      () async =>
          (await database()).customStatement('DROP TRIGGER injected_114'),
    );
    await confirm();
    expect(find.text('Importado'), findsOneWidget);

    // Dos peticiones al núcleo con la misma revisión, además del bloqueo UI.
    await start(file([real(2, concept: 'Doble confirmación')]));
    c = tester
        .widget<ImportReviewScreen>(find.byType(ImportReviewScreen))
        .controller;
    final request = ImportConfirmationRequest(review: c.review!);
    final results = await io(() async {
      final repo = SqliteImportBatchRepository(await database());
      return Future.wait([repo.confirm(request), repo.confirm(request)]);
    });
    expect(results.whereType<ImportConfirmed>(), hasLength(1));
    expect(results.whereType<ImportAlreadyImported>(), hasLength(1));
    expect(await count('import_batches'), 6);
    expect(await count('movements'), 8);
    expect(await count('budgets'), 3);
    final finalImage = await image();
    await close();
    installation = LocalBackupSession(supportDirectory: () async => directory);
    await mount();
    expect(persisted(await image()), persisted(finalImage));
    await route(AppRoutes.importHistory);
    expect(find.text('Historial de importaciones'), findsOneWidget);
    await io(
      () => importReferenceJourney(
        Directory('${directory.path}/reference-ep001'),
      ),
    );
    debugPrint(
      'EP-012: referencia EP-001, 48 presupuestos / 10 reales y totales correctos.',
    );
    debugPrint('EP-012: recorrido completo, rollback y reapertura correctos.');
  } finally {
    await close();
  }
}
