import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/local_backup_session.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/features/diagnostics/diagnostics.dart';
import 'package:myautofinance/features/diagnostics/presentation/diagnostic_controller.dart';
import 'package:myautofinance/features/diagnostics/presentation/diagnostic_screen.dart';
import 'package:myautofinance/features/importing/data/historical_csv_import_adapter.dart';
import 'package:myautofinance/features/importing/data/sha256_import_fingerprint.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/indicators/indicators.dart';
import 'package:myautofinance/features/movements/presentation/pending_movement_screen.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';
import 'package:myautofinance/features/wealth/presentation/wealth_photo_screen.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

import 'diagnostic_journey.dart' show diagnosticDatabaseImage;

/// Mismo guion en host y plataformas, sin sustituir servicios de producción.
/// Los bytes se leen del CSV EP-001 en el host y se inyectan al runner nativo.
Future<void> diagnosticAcceptanceJourney(
  WidgetTester tester,
  Directory directory,
  List<int> historicalCsv, {
  Future<void> Function(String, Map<String, Object?>)? evidence,
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
    for (var i = 0; i < 300; i++) {
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump(const Duration(milliseconds: 50));
      final screen = find.byType(DiagnosticScreen);
      final controller = screen.evaluate().isEmpty
          ? null
          : tester.widget<DiagnosticScreen>(screen).controller;
      final pending = find.byType(PendingMovementScreen);
      final pendingController = pending.evaluate().isEmpty
          ? null
          : tester.widget<PendingMovementScreen>(pending).controller;
      if (i >= 12 &&
          !(controller?.busy ?? false) &&
          !(controller?.checking ?? false) &&
          !(pendingController?.loading ?? false) &&
          !(pendingController?.sending ?? false) &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.textContaining('Cargando').evaluate().isEmpty &&
          find.textContaining('Leyendo').evaluate().isEmpty) {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        return;
      }
    }
    fail('El recorrido integrado SQLite no terminó.');
  }

  Future<void> tap(Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(target));
    await settle();
  }

  Future<void> press(String label) => tap(find.text(label).first);
  Future<void> action(String prefix) => tap(
    find
        .byWidgetPredicate((w) => w is AfAction && w.label.startsWith(prefix))
        .first,
  );
  DiagnosticController controller() =>
      tester.widget<DiagnosticScreen>(find.byType(DiagnosticScreen)).controller;
  DiagnosticReport report() => controller().report!;
  List<DiagnosticFinding> findings(DiagnosticRule rule) =>
      report().results.singleWhere((r) => r.rule == rule).findings;
  Future<Map<String, Object?>> image() =>
      io(() async => diagnosticDatabaseImage(await local.store.open()));
  Future<void> record(String stage) async {
    final current = report();
    final before = await image();
    final reading = await io(
      () async => (await local.wealth()).readMonth(current.selectedMonth),
    );
    final evaluation = await io(
      () async => (await local.indicators()).engine.evaluate(
        'colchon_emergencia',
        current.selectedMonth,
      ),
    );
    await evidence?.call(stage, {
      'month': current.selectedMonth.value,
      'datasetId': current.revision.dataset.datasetId,
      'revision': current.revision.dataset.revision,
      'generation': current.revision.generation,
      'executedAt': current.executedAt.toUtc().toIso8601String(),
      'obsolete': controller().obsolete,
      'movementCount': (before['movements']! as List).length,
      'budgetCount': (before['budgets']! as List).length,
      'photoStatus': reading.status.name,
      'pendingAccounts': reading.pending.map((a) => a.name).toList(),
      'liquidAssetsCents': reading.totals?.liquidAssetsCents,
      'netWorthCents': reading.totals?.netWorthCents,
      'indicator': switch (evaluation.result) {
        CalculatedIndicator(:final value) => {
          'numerator': value.numerator.toString(),
          'denominator': value.denominator.toString(),
        },
        UnavailableIndicator(:final code) => {'unavailable': code},
      },
      'rules': {
        for (final r in current.results)
          r.rule.code: {'status': r.status.name, 'findings': r.findings.length},
      },
    });
    expect(
      await image(),
      before,
      reason: 'Acreditar resultados también es solo lectura',
    );
    debugPrint(
      'MA-TSK-202: $stage, revisión ${current.revision.dataset.revision}',
    );
  }

  Future<void> run() async {
    final before = await image();
    await press(
      controller().execution == null
          ? 'Ejecutar diagnóstico'
          : 'Repetir diagnóstico',
    );
    expect(controller().obsolete, isFalse);
    expect(
      report().results.every((r) => r.status != DiagnosticRuleStatus.notRun),
      isTrue,
    );
    expect(await image(), before, reason: 'Diagnosticar no repara ni escribe');
  }

  Future<ImportSession> session(List<int> bytes, String name) async {
    final file = ImportFile.fromBytes(
      bytes: bytes,
      fingerprint: const Sha256ImportFingerprint(),
      source: ImportSource.historicalCsv,
      originalName: name,
    );
    return ImportSession(
      file: file,
      interpretation: await const HistoricalCsvImportAdapter().interpret(file),
    );
  }

  Future<void> back() async {
    await tester.binding.handlePopRoute();
    await settle();
  }

  Future<void> editPhoto(Map<String, String> values) async {
    await press('Completar foto · 2026-02-01');
    final screen = tester.widget<WealthPhotoScreen>(
      find.byType(WealthPhotoScreen),
    );
    expect(screen.month.value, '2026-02-01');
    for (final entry in values.entries) {
      final field = find.byKey(ValueKey('photo-value-${entry.key}'));
      await tester.ensureVisible(field);
      await tester.enterText(field, entry.value);
      await tester.pump();
    }
    await press('Guardar foto');
    // El editor retorna al diagnóstico usando la pila propietaria.
    if (find.byType(DiagnosticScreen).evaluate().isEmpty) await back();
    expect(find.byType(DiagnosticScreen), findsOneWidget);
    expect(controller().obsolete, isTrue);
    expect(navigation.period, NavigationPeriod(2026, 2));
  }

  Future<void> indicator(int numerator, int denominator) async {
    final before = await image();
    final value = await io(
      () async => (await local.indicators()).engine.evaluate(
        'colchon_emergencia',
        Month(2026, 2),
      ),
    );
    final calculated = value.result as CalculatedIndicator;
    expect(calculated.value.numerator, BigInt.from(numerator));
    expect(calculated.value.denominator, BigInt.from(denominator));
    expect(await image(), before);
  }

  try {
    expect(
      await io(local.open),
      isTrue,
      reason: local.controller.startupMessage,
    );
    final original = await session(historicalCsv, 'historico-sintetico.csv');
    final categories = <ImportCategoryReference, ImportNewCategory>{};
    for (final row in original.interpretation.rows) {
      final reference = switch (row) {
        InterpretedMovement() => row.category,
        InterpretedBudget() => row.category,
      };
      if (reference == null) continue;
      for (var depth = 1; depth <= reference.path.length; depth++) {
        final path = reference.path.take(depth).toList();
        categories[ImportCategoryReference(path)] = ImportNewCategory(
          name: path.last,
          parent: depth == 1
              ? null
              : ImportCategoryTarget.proposed(
                  ImportCategoryReference(path.take(depth - 1).toList()),
                ),
          isIncome: depth == 1 ? path.first == 'Ingresos' : null,
        );
      }
    }
    final imports = await io(local.imports);
    final review = await io(
      () => imports.previewer.preview(
        original,
        bindings: ImportReferenceBindings(
          newAccounts: {
            ImportAccountReference.named('Cuenta principal'): ImportNewAccount(
              name: 'Cuenta principal',
              activeFrom: Month(2026, 1),
              liquidity: Liquidity.liquid,
            ),
          },
          newCategories: categories,
        ),
      ),
    );
    expect(review.issues, isEmpty);
    final confirmed = await io(
      () =>
          imports.confirmer.confirm(ImportConfirmationRequest(review: review)),
    ) as ImportConfirmed;
    expect(confirmed.movementCount, 10);
    expect(confirmed.budgetCount, 48);
    final imported = await image();
    final renamed = await session(
      historicalCsv,
      'mismos-bytes-renombrados.csv',
    );
    final repeatedReview = await io(() => imports.previewer.preview(renamed));
    final repeated = await io(
      () => imports.confirmer.confirm(
        ImportConfirmationRequest(review: repeatedReview),
      ),
    );
    expect(repeated, isA<ImportAlreadyImported>());
    expect(
      await image(),
      imported,
      reason: 'Repetición exacta: cero altas, revisión intacta',
    );

    final wealth = await io(local.wealth);
    final principal = (await io(wealth.catalog)).single.id;
    final saving = (await io(
      () => wealth.create(
        name: 'Cuenta de ahorro',
        kind: AccountKind.account,
        activeFrom: Month(2026, 1),
        liquidity: Liquidity.liquid,
      ),
    )).account.id;
    final portfolio = (await io(
      () => wealth.create(
        name: 'Cartera',
        kind: AccountKind.portfolio,
        activeFrom: Month(2026, 1),
        liquidity: Liquidity.medium,
      ),
    )).account.id;
    final debt = (await io(
      () => wealth.create(
        name: 'Deuda familiar',
        kind: AccountKind.debt,
        activeFrom: Month(2026, 1),
      ),
    )).account.id;
    await io(
      () => wealth.savePhoto(Month(2026, 1), {
        principal: 600000,
        saving: 300000,
        portfolio: 1000000,
        debt: 500000,
      }),
    );
    final january = (await image())['wealth_values'];
    await tester.pumpWidget(
      AutofinanceApp(localSession: local, navigationSession: navigation),
    );
    await settle();
    await press('Diagnóstico de coherencia');
    await run();
    expect(
      report().isConformant,
      isTrue,
      reason: 'Ocio sin presupuesto y dos Café legítimos',
    );
    await record('csv-repetido-sin-altas');

    final lines = const LineSplitter().convert(utf8.decode(historicalCsv));
    final coffee = lines.firstWhere((line) => line.contains(';Café;'));
    final second = await session(
      utf8.encode(
        '${lines.first}\n$coffee\n'
        '2026-01-07;Pendiente sintético;-12.34;REAL;;;;Cuenta principal;\n',
      ),
      'segundo-sintetico.csv',
    );
    final secondReview = await io(() => imports.previewer.preview(second));
    expect(secondReview.overlaps, isNotEmpty);
    final overlapImport = await io(
      () => imports.confirmer.confirm(
        ImportConfirmationRequest(
          review: secondReview,
          reviewedOverlapKeys: secondReview.overlaps.map((o) => o.key).toSet(),
        ),
      ),
    );
    expect(overlapImport, isA<ImportConfirmed>());
    await settle();
    expect(controller().obsolete, isTrue);
    final oldRevision = report().revision.dataset.revision;
    await run();
    expect(report().revision.dataset.revision, greaterThan(oldRevision));
    expect(findings(DiagnosticRule.importCoincidence), hasLength(2));
    expect(
      findings(DiagnosticRule.importCoincidence)
          .every((f) => f.severity == DiagnosticSeverity.warning),
      isTrue,
    );
    expect(findings(DiagnosticRule.uncategorizedMovement), hasLength(1));
    expect(
      report().results
          .where((r) => r.rule.severity == DiagnosticSeverity.error)
          .every((r) => r.findings.isEmpty),
      isTrue,
    );
    final beforeOrigin = await image();
    await press('Posible coincidencia entre lotes');
    await action('Abrir lote ');
    await back();
    expect(controller().obsolete, isFalse);
    expect(await image(), beforeOrigin);
    await press('Movimiento sin categoría');
    await action('Abrir bandeja ·');
    expect(find.byType(PendingMovementScreen), findsOneWidget);
    await press('Categorizar Pendiente sintético');
    await press('Ocio');
    await press('Seleccionar');
    await press('Guardar categoría');
    final pendingScreen = tester.widget<PendingMovementScreen>(
      find.byType(PendingMovementScreen),
    );
    expect(pendingScreen.controller.operationActive, isFalse);
    expect(pendingScreen.controller.page!.totalCount, 0);
    await press('Volver a Diagnóstico');
    expect(
      find.byType(DiagnosticScreen),
      findsOneWidget,
      reason:
          'Retorno desde bandeja; pendientes visibles=${find.byType(PendingMovementScreen).evaluate().length}; '
          'diagnósticos en pila=${find.byType(DiagnosticScreen, skipOffstage: false).evaluate().length}',
    );
    expect(controller().obsolete, isTrue);
    await record('categorizado-resultado-obsoleto');
    await run();
    expect(findings(DiagnosticRule.uncategorizedMovement), isEmpty);
    expect(findings(DiagnosticRule.importCoincidence), hasLength(2));
    final db = await io(local.store.open);
    final coffees = (await io(
      () => SqliteMovementRepository(db).readYear(2026),
    )).where((r) => r.data.concept == 'Café').toList();
    expect(coffees, hasLength(3));
    expect(coffees.map((r) => r.id).toSet(), hasLength(3));
    expect(
      coffees
          .where((r) => r.batchId == confirmed.batch.id)
          .map((r) => r.sourceOrdinal),
      unorderedEquals([54, 55]),
    );
    await record('pendiente-resuelto-avisos-conservados');

    await io(() => navigation.selectPeriod(NavigationPeriod(2026, 2)));
    await settle();
    expect(controller().obsolete, isTrue);
    await run();
    expect(findings(DiagnosticRule.absentPhoto), hasLength(1));
    expect((await io(() => wealth.readMonth(Month(2026, 2)))).values, isEmpty);
    await press('Foto ausente');
    await editPhoto({principal: '6200', debt: '4800'});
    await run();
    expect(findings(DiagnosticRule.incompletePhoto), hasLength(1));
    final partial = await io(() => wealth.readMonth(Month(2026, 2)));
    expect(partial.totals, isNull);
    expect(
      partial.pending.map((a) => a.id),
      unorderedEquals([saving, portfolio]),
    );
    await record('foto-incompleta-sin-acarreo');
    await press('Foto incompleta');
    await editPhoto({saving: '0', portfolio: '10500'});
    await run();
    expect(findings(DiagnosticRule.incompletePhoto), isEmpty);
    expect(findings(DiagnosticRule.unavailableIndicator), isEmpty);
    final complete = await image();
    expect(
      (await io(() => wealth.readMonth(Month(2026, 2)))).totals!.netWorthCents,
      1190000,
    );
    await indicator(31, 15);
    await record('foto-completa-cero-valido-colchon-2-07');

    // Corrección desde el editor propietario en el mismo periodo, sin una
    // reparación desde diagnóstico ni crear nuevas identidades de valoración.
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .pushNamed('/patrimonio?a=2026&m=02');
    await settle();
    await press('Registrar / editar foto');
    final mainField = find.byKey(ValueKey('photo-value-$principal'));
    await tester.ensureVisible(mainField);
    await tester.enterText(mainField, '6300');
    await press('Guardar foto');
    await back();
    if (find.byType(DiagnosticScreen).evaluate().isEmpty) await back();
    expect(controller().obsolete, isTrue);
    await run();
    await indicator(21, 10);
    final corrected = await image();
    final beforeValues = (complete['wealth_values']! as List)
        .cast<Map<String, Object?>>();
    final afterValues = (corrected['wealth_values']! as List)
        .cast<Map<String, Object?>>();
    expect(afterValues.map((r) => r['id']), beforeValues.map((r) => r['id']));
    final januaryIds = (january! as List)
        .cast<Map<String, Object?>>()
        .map((r) => r['id'])
        .toSet();
    expect(
      afterValues.where((r) => januaryIds.contains(r['id'])).toList(),
      january,
    );
    expect(
      (await io(() => wealth.readMonth(Month(2026, 2)))).totals!.netWorthCents,
      1200000,
    );
    expect(navigation.period, NavigationPeriod(2026, 2));
    await record('correccion-febrero-colchon-2-10');

    final generation = report().revision.generation;
    await io(local.controller.create);
    expect(local.controller.error, isNull);
    final copy = local.controller.listing!.entries.single.backupId;
    await io(() => local.controller.restore(copy, confirmed: true));
    expect(local.controller.restoreResult!.status, LocalRestoreStatus.restored);
    await settle();
    expect(controller().obsolete, isTrue);
    await run();
    expect(report().revision.generation, greaterThan(generation));
    expect(await image(), corrected);
    await indicator(21, 10);
    await record('recuperacion-y-repeticion-explicita');
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await io(local.store.close);
    local.controller.dispose();
    navigation.dispose();
    await local.categoryInvalidation.close();
  }
}
