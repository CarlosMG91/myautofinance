import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/features/synchronization/export_saving.dart';
import 'package:myautofinance/features/synchronization/presentation/export_controller.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';

import 'export_support.dart';

void main() {
  test(
    'Valida meses antes de capturar; permite un único mes inclusivo',
    () async {
      final f = ExportFixture();
      final c = f.controller();
      addTearDown(c.dispose);
      for (final range in [
        ('2026-02', '2026-01'),
        ('2026-13', '2026-13'),
        ('', ''),
        ('0000-01', '2026-01'),
      ]) {
        c.select(months: true, from: range.$1, through: range.$2);
        await c.save();
        expect(c.message, contains('Elige ambos meses'));
        expect(f.filters, isEmpty);
      }
      c.select(from: '2026-02', through: '2026-02');
      await c.save();
      expect(f.filters.single!.toJson(), {
        'mode': 'months',
        'fromMonth': '2026-02-01',
        'throughMonth': '2026-02-01',
      });
      expect(c.capturedState!.revision, 1);
      expect(c.capturedAt, DateTime.utc(2026, 10, 17, 8, 1));
      expect(
        f.requests.single.suggestedName,
        'autofinance-datos-20261017T080100Z.zip',
      );
      expect(f.prepared.single.disposals, 1);
    },
  );

  test(
    'Cambio de rango y modo toma otra captura; copia siempre completa',
    () async {
      final f = ExportFixture();
      final c = f.controller();
      addTearDown(c.dispose);
      await c.save();
      c.select(months: true, from: '2026-01', through: '2026-03');
      expect(c.result, isNull);
      expect(c.capturedState, isNull);
      await c.save();
      c.select(mode: ExportMode.complete, from: 'invalid');
      await c.save();
      expect(f.filters[0]!.fromMonth, isNull);
      expect(f.filters[1]!.throughMonth, '2026-03-01');
      expect(f.filters[2], isNull);
      expect(c.exportedScope, 'Todo el histórico');
      expect(f.requests.map((r) => r.zipPath).toSet(), hasLength(3));
      expect(f.prepared.every((p) => p.disposals == 1), isTrue);
    },
  );

  test('No duplica ni cambia selección mientras prepara o guarda', () async {
    final f = ExportFixture()
      ..preparation = Completer<void>()
      ..saving = Completer<ExportSaveResult>();
    final c = f.controller();
    addTearDown(c.dispose);
    final run = c.save();
    expect(c.phase, ExportPhase.preparing);
    await c.save();
    c.select(mode: ExportMode.complete);
    expect(c.mode, ExportMode.data);
    expect(f.filters, hasLength(1));
    f.preparation!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(c.phase, ExportPhase.saving);
    expect(c.result, isNull);
    expect(f.prepared.single.disposals, 0);
    c.cancelPreparation();
    await c.save();
    expect(f.requests, hasLength(1));
    f.saving!.complete(
      const ExportSaved(location: 'content://synthetic/document/1'),
    );
    await run;
    expect(c.result, isA<ExportSaved>());
    expect(f.prepared.single.disposals, 1);
    expect(c.busy, isFalse);
  });

  test('Cancelar preparación no abre selector; permite reintentar', () async {
    final f = ExportFixture()..preparation = Completer<void>();
    final c = f.controller();
    addTearDown(c.dispose);
    final run = c.save();
    c.cancelPreparation();
    f.preparation!.complete();
    await run;
    expect(c.message, contains('cancelada'));
    expect(f.requests, isEmpty);
    f.preparation = null;
    await c.save();
    expect(c.result, isA<ExportSaved>());
  });

  for (final outcome in <ExportSaveResult>[
    const ExportSaveCancelled(),
    const ExportSaveFailed(ExportSaveFailureCode.conflict),
    const ExportSaveFailed(
      ExportSaveFailureCode.writeFailed,
      incompleteMayRemain: true,
    ),
  ]) {
    test(
      'Cancelación/fallo conserva selección, libera ZIP y reintenta explícitamente: $outcome',
      () async {
        final f = ExportFixture()..outcome = outcome;
        final c = f.controller();
        addTearDown(c.dispose);
        c.select(months: true, from: '2026-01', through: '2026-02');
        await c.save();
        expect(c.result, same(outcome));
        expect(c.from, '2026-01');
        expect(c.through, '2026-02');
        expect(f.prepared.single.disposals, 1);
        expect(f.requests, hasLength(1));
        if (outcome is ExportSaveFailed && outcome.incompleteMayRemain) {
          expect(c.message, contains('incompleto'));
        }
        f.outcome = const ExportSaved();
        await c.save();
        expect(f.prepared, hasLength(2));
        expect(c.capturedState!.revision, 2);
        expect(c.dirty, isFalse);
      },
    );
  }

  test('Fallo de generación no guarda ni filtra excepciones; reintento obtiene captura nueva', () async {
    final f = ExportFixture()..prepareError = StateError('private SQL secret');
    final c = f.controller();
    addTearDown(c.dispose);
    await c.save();
    expect(c.message, isNot(contains('secret')));
    expect(f.requests, isEmpty);
    f.prepareError = const DataExportFailure(
      DataExportFailureCode.invalidSnapshot,
    );
    await c.save();
    expect(c.message, contains('validar'));
    f.prepareError = null;
    await c.save();
    expect(c.result, isA<ExportSaved>());
  });

  test('Error inesperado de guardado no muestra éxito; cleanup no borra resultado confirmado', () async {
    final f = ExportFixture()..saveError = StateError('private destination');
    final c = f.controller();
    addTearDown(c.dispose);
    await c.save();
    expect(c.result, isNull);
    expect(c.message, contains('Revisa el destino'));
    expect(f.prepared.single.disposals, 1);
    f.saveError = null;
    f.cleanupFails = true;
    await c.save();
    expect(c.result, isA<ExportSaved>());
    expect(c.cleanupWarning, contains('temporal'));
  });

  test(
    'Desmontar durante escritura conserva temporal hasta resultado y lo libera',
    () async {
      final f = ExportFixture()..saving = Completer<ExportSaveResult>();
      final c = f.controller();
      final run = c.save();
      await Future<void>.delayed(Duration.zero);
      c.dispose();
      expect(f.prepared.single.disposals, 0);
      f.saving!.complete(const ExportSaved());
      await run;
      expect(f.prepared.single.disposals, 1);
    },
  );
}
