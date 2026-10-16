import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/navigation/diagnostic_route.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/app/regional.dart';
import 'package:myautofinance/core/persistence/unit_of_work.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/diagnostics/diagnostics.dart';
import 'package:myautofinance/features/diagnostics/presentation/diagnostic_controller.dart';
import 'package:myautofinance/features/diagnostics/presentation/diagnostic_screen.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/indicators/indicators.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

const recordId = '00000000-0000-4000-8000-000000000001';
const secondId = '00000000-0000-4000-8000-000000000002';

class SyntheticDiagnosticSource
    implements DiagnosticReadSource, DiagnosticReadSession {
  int runs = 0, revisionNumber = 1;
  bool fail = false, unavailable = false;
  Completer<void>? wait;
  final evidence = <DiagnosticEvidence>[];
  @override
  DiagnosticRevision get revision => DiagnosticRevision(
    DatasetState(datasetId: 'synthetic', revision: revisionNumber),
    generation: 1,
  );
  @override
  Future<DiagnosticRevision> currentRevision() async {
    if (fail) throw StateError('Synthetic read failure');
    return revision;
  }

  @override
  Future<DiagnosticRevision> readRevision() => currentRevision();
  @override
  Future<T> read<T>(Future<T> Function(DiagnosticReadSession) operation) async {
    runs++;
    await wait?.future;
    return operation(this);
  }

  @override
  Future<DiagnosticRuleResult> check(DiagnosticRule rule, Month month) async =>
      unavailable && rule == DiagnosticRule.unavailableIndicator
      ? DiagnosticRuleResult.notRun(
          rule,
          DiagnosticNotRunReason.dependencyUnavailable,
        )
      : DiagnosticRuleResult.completed(
          rule,
          evidence: evidence.where((e) => e.rule == rule).toList(),
        );
}

MovementRecord syntheticMovement(String id, {String? batch, int? ordinal}) =>
    MovementRecord(
      id: id,
      data: MovementInput(
        accountId: recordId,
        valueDate: ValueDate(2026, 1, 5),
        concept: 'Café sintético',
        amountCents: -1000,
      ),
      batchId: batch,
      sourceOrdinal: ordinal,
      importRowId: batch == null ? null : id,
    );

void main() {
  test('controlador: manual, cancelación, notificación, revisión, mes y repetición', () async {
    final source = SyntheticDiagnosticSource();
    final events = StreamController<int>.broadcast(sync: true);
    final c = DiagnosticController(
      DiagnosticExecutor(source),
      changes: events.stream,
    );
    expect(source.runs, 0);
    source.wait = Completer();
    final running = c.run(Month(2026, 1));
    await Future<void>.delayed(Duration.zero);
    expect(c.busy, isTrue);
    c.cancel();
    source.wait!.complete();
    await running;
    expect(
      (c.execution as DiagnosticFailed).reason,
      DiagnosticSessionFailure.cancelled,
    );
    source.wait = null;
    await c.run(Month(2026, 1));
    expect(c.report!.isConformant, isTrue);
    c.filter(DiagnosticSeverity.pending);
    events.add(1);
    await Future<void>.delayed(Duration.zero);
    expect(c.obsolete, isFalse); // Leer/crear una copia no cambia los datos.
    source.revisionNumber++;
    events.add(2);
    await Future<void>.delayed(Duration.zero);
    expect(c.obsolete, isTrue);
    expect(source.runs, 2);
    await c.run(Month(2026, 1));
    expect(c.severity, DiagnosticSeverity.pending);
    source.revisionNumber++;
    await c.validate(Month(2026, 1));
    expect(c.obsolete, isTrue);
    await c.run(Month(2026, 1));
    await c.validate(Month(2026, 2));
    expect(c.obsolete, isTrue);
    c.dispose();
    await events.close();
  });

  for (final width in [1440.0, 412.0, 320.0]) {
    testWidgets('estados manuales, cobertura y reflujo $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = SyntheticDiagnosticSource();
      final session = NavigationSession(
        initialContext: NavigationContext(
          destination: SessionDestination.diagnostics,
          period: NavigationPeriod(2026, 1),
        ),
      );
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(width == 320 ? 2 : 1),
          ),
          child: AutofinanceApp(
            diagnostics: DiagnosticExecutor(source),
            navigationSession: session,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(source.runs, 0);
      await tester.ensureVisible(find.text('Ejecutar diagnóstico'));
      await tester.tap(find.text('Ejecutar diagnóstico'));
      await tester.pumpAndSettle();
      expect(find.text('Sin hallazgos'), findsOneWidget);
      expect(find.text('9 de 9 reglas ejecutadas'), findsOneWidget);
      source.unavailable = true;
      await tester.ensureVisible(find.text('Repetir diagnóstico'));
      await tester.tap(find.text('Repetir diagnóstico'));
      await tester.pumpAndSettle();
      expect(find.text('Revisión incompleta'), findsOneWidget);
      expect(find.text('8 de 9 reglas ejecutadas'), findsOneWidget);
      await tester.ensureVisible(
        find.text('Ver cobertura de las nueve reglas'),
      );
      await tester.tap(find.text('Ver cobertura de las nueve reglas'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Regla no ejecutada'), findsOneWidget);
      source.fail = true;
      await tester.ensureVisible(find.text('Repetir diagnóstico'));
      await tester.tap(find.text('Repetir diagnóstico'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No se pudo leer la base local'),
        findsOneWidget,
      );
      expect(find.text('9 de 9 reglas ejecutadas'), findsNothing);
      expect(find.text('Abrir Recuperación local'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('carga/cancelación sin conformidad y sin informe anterior', (
    tester,
  ) async {
    final source = SyntheticDiagnosticSource()..wait = Completer();
    await tester.pumpWidget(
      AutofinanceApp(
        diagnostics: DiagnosticExecutor(source),
        navigationSession: NavigationSession(
          initialContext: NavigationContext(
            destination: SessionDestination.diagnostics,
            period: NavigationPeriod(2026, 1),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ejecutar diagnóstico'));
    await tester.pump();
    expect(find.text('Cancelar diagnóstico'), findsOneWidget);
    await tester.ensureVisible(find.text('Cancelar diagnóstico'));
    await tester.tap(find.text('Cancelar diagnóstico'));
    source.wait!.complete();
    await tester.pumpAndSettle();
    expect(
      find.text('Diagnóstico cancelado. No hay resultado conforme.'),
      findsOneWidget,
    );
    expect(find.text('Sin hallazgos'), findsNothing);
    source.wait = Completer<void>();
    await tester.ensureVisible(find.text('Repetir diagnóstico'));
    await tester.tap(find.text('Repetir diagnóstico'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    source.wait!.complete();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
      find.text('Diagnóstico cancelado. No hay resultado conforme.'),
      findsOneWidget,
    );
    expect(source.runs, 2);
  });

  testWidgets(
    'severidad mantiene totales, IDs/mes histórico, retorno y referencia eliminada',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = SyntheticDiagnosticSource();
      source.evidence.addAll([
        UncategorizedMovementEvidence(syntheticMovement(recordId)),
        BudgetOverlapEvidence(
          ancestor: BudgetRecord(
            id: recordId,
            data: BudgetInput(
              month: BudgetMonth(2025, 12),
              categoryId: recordId,
              amountCents: 0,
            ),
          ),
          descendant: BudgetRecord(
            id: secondId,
            data: BudgetInput(
              month: BudgetMonth(2025, 12),
              categoryId: secondId,
              amountCents: -200,
            ),
          ),
        ),
      ]);
      final session = NavigationSession(
        initialContext: NavigationContext(
          destination: SessionDestination.diagnostics,
          period: NavigationPeriod(2026, 10),
        ),
      );
      addTearDown(session.dispose);
      final opened = <String>[];
      var exists = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: AfTheme.light(),
          locale: AppRegional.locale,
          supportedLocales: AppRegional.supportedLocales,
          localizationsDelegates: AppRegional.delegates,
          initialRoute: '/diagnostico?a=2026&m=10',
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (context) {
              if (settings.name!.startsWith('/diagnostico')) {
                return DiagnosticRoute(
                  settings: settings,
                  executor: DiagnosticExecutor(source),
                  session: session,
                  exists: (entity, id) async => exists,
                );
              }
              opened.add(settings.name!);
              return Scaffold(
                body: TextButton(
                  onPressed: () {
                    source.revisionNumber++;
                    Navigator.pop(context);
                  },
                  child: const Text('Volver desde origen'),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ejecutar diagnóstico'));
      await tester.pumpAndSettle();
      expect(find.text('Errores: 1'), findsOneWidget);
      expect(find.text('Pendientes: 1'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Errores'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Errores'));
      await tester.pumpAndSettle();
      expect(find.text('Movimiento sin categoría'), findsNothing);
      await tester.ensureVisible(find.text('Presupuesto padre y descendiente'));
      await tester.tap(find.text('Presupuesto padre y descendiente'));
      await tester.pumpAndSettle();
      final action = find.text('Abrir partida $recordId · 2025-12-01').first;
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(opened.last, '/presupuesto/partidas/$recordId?a=2025&m=12');
      await tester.tap(find.text('Volver desde origen'));
      await tester.pumpAndSettle();
      expect(session.period, NavigationPeriod(2026, 10));
      expect(source.runs, 1);
      expect(find.textContaining('Resultado obsoleto.'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Errores'))
            .selected,
        isTrue,
      );
      exists = false;
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(opened.last, '/presupuesto/partidas?a=2026&m=10');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('detalle conserva importes y ambos registros/lotes legítimos', (
    tester,
  ) async {
    final source = SyntheticDiagnosticSource()
      ..evidence.add(
        ImportCoincidenceEvidence(
          syntheticMovement(recordId, batch: recordId, ordinal: 2),
          syntheticMovement(secondId, batch: secondId, ordinal: 600),
        ),
      );
    final c = DiagnosticController(DiagnosticExecutor(source));
    addTearDown(c.dispose);
    await c.run(Month(2026, 1));
    await tester.pumpWidget(
      MaterialApp(
        theme: AfTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: DiagnosticScreen(
              controller: c,
              month: Month(2026, 1),
              onAction: (_) async {},
              onRecord: (_, _, _) async {},
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Posible coincidencia entre lotes'));
    await tester.tap(find.text('Posible coincidencia entre lotes'));
    await tester.pumpAndSettle();
    expect(find.textContaining('−10,00 €'), findsNWidgets(3));
    expect(find.text('Abrir lote $secondId · fila 600'), findsOneWidget);
    expect(find.text('Abrir movimiento $secondId'), findsOneWidget);
  });

  testWidgets(
    'causa de ingresos abre marzo del año evaluado sin pasar por Indicadores',
    (tester) async {
      final month = Month(2026, 10);
      final definition = IndicatorCatalog.v1().definition('colchon_emergencia');
      final result = UnavailableIndicator(
        reason: definition.reasons.singleWhere(
          (r) => r.code == 'ingresos_incompletos',
        ),
        detail: IndicatorMissingDetail(pendingMonths: [3]),
      );
      final source = SyntheticDiagnosticSource()
        ..evidence.add(
          UnavailableIndicatorEvidence(
            IndicatorEvaluation(
              definition: definition,
              month: month,
              result: result,
              inputs: IndicatorInputs(month: month),
            ),
          ),
        );
      final c = DiagnosticController(DiagnosticExecutor(source));
      addTearDown(c.dispose);
      await c.run(month);
      final opened = <Month>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AfTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: DiagnosticScreen(
                controller: c,
                month: month,
                onAction: (_) async =>
                    fail('Debe abrir presupuesto del mes pendiente.'),
                onRecord: (entity, id, month) async {
                  expect(entity, DiagnosticEntity.budget);
                  expect(id, isEmpty);
                  opened.add(month);
                },
              ),
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('Indicador sin dato'));
      await tester.tap(find.text('Indicador sin dato'));
      await tester.pumpAndSettle();
      final action = find.text('Completar presupuesto de ingresos · 2026');
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(opened.single.value, '2026-03-01');
    },
  );

  testWidgets('destinos tipados, identidades, periodos y fallo de referencia', (
    tester,
  ) async {
    final source = SyntheticDiagnosticSource();
    final session = NavigationSession(
      initialContext: NavigationContext(
        destination: SessionDestination.diagnostics,
        period: NavigationPeriod(2026, 10),
      ),
    );
    addTearDown(session.dispose);
    final opened = <String>[];
    var failure = false;
    Completer<void>? pendingReference;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: AfTheme.light(),
        locale: AppRegional.locale,
        supportedLocales: AppRegional.supportedLocales,
        localizationsDelegates: AppRegional.delegates,
        initialRoute: '/diagnostico?a=2026&m=10',
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (context) {
            if (settings.name!.startsWith('/diagnostico')) {
              return DiagnosticRoute(
                settings: settings,
                executor: DiagnosticExecutor(source),
                session: session,
                exists: (entity, id) async {
                  await pendingReference?.future;
                  if (failure) throw StateError('Synthetic failure');
                  return true;
                },
              );
            }
            opened.add(settings.name!);
            return const Scaffold(body: Text('Destino de prueba'));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final screen = tester.widget<DiagnosticScreen>(
      find.byType(DiagnosticScreen),
    );
    for (final entry in <(DiagnosticAction, String)>[
      (const OpenPendingMovement(recordId), '/pendientes-categorizacion'),
      (
        const OpenImportBatch(recordId, sourceOrdinal: 600),
        '/importaciones/lotes/$recordId',
      ),
      (OpenWealthPhoto(Month(2025, 2)), '/patrimonio/foto?a=2025&m=02'),
      (const OpenIncomeBudget(2025), '/presupuesto/mensual?a=2025&m=10'),
      (const OpenDiagnosticCatalog(DiagnosticEntity.category), '/categorias'),
      (const OpenLocalRecovery(), '/copias-locales'),
    ]) {
      unawaited(screen.onAction(entry.$1));
      await tester.pumpAndSettle();
      expect(opened.last, entry.$2);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
    }
    for (final entry in <(DiagnosticEntity, String)>[
      (DiagnosticEntity.movement, '/movimientos/$recordId?a=2024&m=03'),
      (DiagnosticEntity.account, '/patrimonio/fichas/$recordId?a=2024&m=03'),
      (
        DiagnosticEntity.importRow,
        '/importaciones/origen/$recordId?a=2024&m=03',
      ),
    ]) {
      unawaited(screen.onRecord(entry.$1, recordId, Month(2024, 3)));
      await tester.pumpAndSettle();
      expect(opened.last, entry.$2);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
    }
    final count = opened.length;
    failure = true;
    await screen.onRecord(DiagnosticEntity.movement, recordId, Month(2024, 3));
    await tester.pump();
    expect(opened.length, count);
    expect(
      find.textContaining('No se pudo leer la referencia.'),
      findsOneWidget,
    );
    expect(source.runs, 0);
    expect(session.period, NavigationPeriod(2026, 10));
    failure = false;
    pendingReference = Completer<void>();
    final opening = screen.onRecord(
      DiagnosticEntity.movement,
      recordId,
      Month(2024, 3),
    );
    await tester.pump();
    await session.selectPeriod(NavigationPeriod(2026, 11));
    pendingReference.complete();
    await opening;
    await tester.pumpAndSettle();
    expect(opened.length, count);
    expect(session.period, NavigationPeriod(2026, 11));
    await tester.pumpWidget(const SizedBox());
  });
}
