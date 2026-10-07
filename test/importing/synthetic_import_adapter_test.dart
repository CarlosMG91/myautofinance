import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/features/importing/data/sha256_import_fingerprint.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';

import '../support/synthetic_import_adapter.dart';

const _fingerprint = Sha256ImportFingerprint();

ImportFile _file(
  List<int> bytes, {
  String name = 'fixture.json',
  ImportSource source = ImportSource.historicalCsv,
}) => ImportFile.fromBytes(
  bytes: bytes,
  fingerprint: _fingerprint,
  source: source,
  originalName: name,
);

List<int> _bytes(Object json) => utf8.encode(jsonEncode(json));

void main() {
  test(
    'interpreta reales y presupuesto, preserva ordinals, originales y signos',
    () async {
      final bytes = _bytes({
        'rows': [
          {
            'kind': 'REAL',
            'ordinal': 2,
            'date': '2026-01-03',
            'concept': 'Café',
            'cents': -1250,
            'account': 'Cuenta sintética',
            'category': null,
            'fields': [
              {'name': 'importe', 'value': '-12.50'},
            ],
          },
          {
            'kind': 'REAL',
            'ordinal': 3,
            'date': '2026-01-03',
            'concept': 'Café',
            'cents': -1250,
            'account': 'Cuenta sintética',
            'category': null,
          },
          {
            'kind': 'PRESUPUESTO',
            'ordinal': 4,
            'month': '2026-01',
            'concept': 'Presupuesto',
            'cents': 0,
            'category': ['Gastos', 'Vivienda'],
            'fields': [
              {'name': 'importe_eur', 'value': '0.00'},
            ],
          },
        ],
      });
      final file = _file(bytes);
      final interpretation = await const SyntheticImportAdapter(
        ImportSource.historicalCsv,
      ).interpret(file);
      final session = ImportSession(file: file, interpretation: interpretation);
      expect(session.isValid, isTrue);
      expect(session.interpretation.rows, hasLength(3));
      final reals = session.interpretation.rows
          .whereType<InterpretedMovement>()
          .toList();
      expect(reals.map((row) => row.amount.internalCents), [-1250, -1250]);
      expect(reals.map((row) => row.account.name), [
        'Cuenta sintética',
        'Cuenta sintética',
      ]);
      expect(reals.first.category, isNull);
      expect(reals.first.originalFields.single.value, '-12.50');
      final budget = session.interpretation.rows
          .whereType<InterpretedBudget>()
          .single;
      expect(budget.amount.originalCents, 0);
      expect(budget.amount.internalCents, 0);
      expect(budget.category.path, ['Gastos', 'Vivienda']);
    },
  );

  test(
    'cuenta pendiente se representa explícitamente; fuente no compatible falla',
    () async {
      final file = _file(
        _bytes({
          'rows': [
            {
              'kind': 'REAL',
              'ordinal': 2,
              'date': '2026-01-03',
              'concept': 'Entrada',
              'cents': 100,
              'category': ['Ingresos'],
            },
          ],
        }),
        source: ImportSource.bankXls,
      );
      final interpretation = await const SyntheticImportAdapter(
        ImportSource.bankXls,
      ).interpret(file);
      final row = interpretation.rows.single as InterpretedMovement;
      expect(row.account.name, isNull);
      expect(
        ImportSession(file: file, interpretation: interpretation).isValid,
        isTrue,
      );

      final wrong = await const SyntheticImportAdapter(
        ImportSource.historicalCsv,
      ).interpret(file);
      expect(wrong.rows, isEmpty);
      expect(wrong.issues.single.code, ImportIssueCode.invalidFile);
    },
  );

  test('acumula fila inválida, lote vacío y bytes renombrados/diferentes reproducibles', () async {
    final badBytes = _bytes({
      'rows': [
        {
          'kind': 'REAL',
          'ordinal': 2,
          'date': '2026-02-30',
          'concept': 'Inválida',
          'cents': 1,
          'account': 'Cuenta',
        },
      ],
    });
    final adapter = const SyntheticImportAdapter(ImportSource.historicalCsv);
    final badFile = _file(badBytes);
    final bad = ImportSession(
      file: badFile,
      interpretation: await adapter.interpret(badFile),
    );
    expect(bad.isValid, isFalse);
    expect(bad.issues.any((issue) => issue.sourceOrdinal == 2), isTrue);

    final emptyFile = _file(_bytes({'rows': []}));
    final empty = ImportSession(
      file: emptyFile,
      interpretation: await adapter.interpret(emptyFile),
    );
    expect(empty.issues.single.code, ImportIssueCode.emptyBatch);

    final first = _file(badBytes);
    final renamed = _file(badBytes, name: 'otro-nombre.json');
    final distinct = _file([...badBytes, 10], name: 'otro-nombre.json');
    expect(first.sha256, renamed.sha256);
    expect(first.sha256, isNot(distinct.sha256));
  });
}
