import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/features/importing/data/openbank_import_adapter.dart';
import 'package:myautofinance/features/importing/data/openbank_reader.dart';
import 'package:myautofinance/features/importing/data/sha256_import_fingerprint.dart';
import 'package:myautofinance/features/importing/importing.dart';

const bankFixturePath = 'docs/ep-014/fixtures/openbank-xhtml-sintetico.xls';
List<int> bankFixture() => File(bankFixturePath).readAsBytesSync();
ImportFile bankFile(List<int> bytes, {String name = 'sintético.xls'}) =>
    ImportFile.fromBytes(
      bytes: bytes,
      fingerprint: const Sha256ImportFingerprint(),
      source: ImportSource.bankXls,
      originalName: name,
    );

void main() {
  const reader = OpenbankReader();
  test('XHTML original: fecha de valor, signo exacto, entidades, originales y duplicados legítimos', () async {
    final expected = jsonDecode(
      File('docs/ep-014/fixtures/openbank-xhtml-esperado.json')
          .readAsStringSync(),
    ) as Map;
    final file = bankFile(bankFixture());
    expect(file.sha256, expected['sha256']);
    final result = reader.read(file.bytes);
    expect(result.issues.map((i) => i.reason), isEmpty);
    expect(result.records.length, expected['count']);
    expect(result.records.map((r) => r.physicalRow), expected['physicalRows']);
    expect(result.records.map((r) => r.valueDate), expected['valueDates']);
    expect(result.records.map((r) => r.amountCents), expected['amounts']);
    expect(
      result.records.fold<int>(0, (s, r) => s + r.amountCents),
      expected['signedCents'],
    );
    expect(result.records[1].concept, 'Café & té sintético');
    expect(result.records[1].concept, result.records[2].concept);
    final adapted = await const OpenbankImportAdapter().interpret(file);
    expect(adapted.issues, isEmpty);
    expect(adapted.rows, hasLength(4));
    for (final r in adapted.rows.cast<InterpretedMovement>()) {
      expect(r.category, isNull);
      expect(r.account, const ImportAccountReference.selectedAccount());
      expect(r.amount.originalCents, r.amount.internalCents);
      expect(
        r.originalFields.map((f) => f.name),
        containsAll([
          'fila_física',
          'Número de Cuenta',
          'Fecha Operación',
          'Fecha Valor',
          'Importe',
          'Saldo',
        ]),
      );
    }
    expect(
      adapted.rows[1].originalFields
          .firstWhere((f) => f.name == 'Fecha Operación')
          .value
          .trim(),
      '19/02/2026',
    );
  });

  final mutations = <String, String Function(String)>{
    'fecha de valor inexistente': (s) =>
        s.replaceFirst('20/02/2026', '31/02/2026'),
    'cero REAL': (s) => s.replaceFirst('1.200,00', '0,00'),
    'desbordamiento': (s) => s.replaceFirst('1.200,00', '92233720368547758,08'),
    'decimal incorrecto': (s) => s.replaceFirst('1.200,00', '1200.001'),
    'agrupación incorrecta': (s) => s.replaceFirst('1.200,00', '1.20,00'),
    'concepto vacío': (s) =>
        s.replaceFirst('TRANSFERENCIA SINTETICA ENTRANTE', ''),
    'saldo inválido': (s) => s.replaceFirst('800,00', 'xxx'),
    'cabecera distinta': (s) => s.replaceFirst('Fecha Valor', 'Otra Fecha'),
    'moneda desconocida': (s) => s.replaceFirst('2.000,00 EUR', '2.000,00 USD'),
    'codificación distinta': (s) =>
        s.replaceFirst('charset=iso-8859-1', 'charset=utf-8'),
    'XML truncado': (s) => s.substring(0, s.length - 30),
    'segunda tabla': (s) => s.replaceFirst('</body>', '<table /></body>'),
    'contenido fuera de tabla': (s) =>
        s.replaceFirst('</body>', '<td>extra</td></body>'),
    'fila intermedia vacía': (s) => s.replaceFirst(
      RegExp(r'<tr style="height:30pt[^>]*>.*?</tr>', dotAll: true),
      '<tr>${List.filled(10, '<td />').join()}</tr>',
    ),
  };
  for (final entry in mutations.entries) {
    test('Rechazo completo: ${entry.key}', () {
      final result = reader.read(
        latin1.encode(entry.value(latin1.decode(bankFixture()))),
      );
      expect(result.records, isEmpty);
      expect(result.issues, isNotEmpty);
    });
  }
  test('Diagnóstico localiza tabla, fila física y campo; otra fuente y binarios rechazados', () async {
    final invalid = reader.read(
      latin1.encode(
        latin1.decode(bankFixture()).replaceFirst('1.200,00', '0,00'),
      ),
    );
    expect(invalid.issues.single.sourceOrdinal, 12);
    expect(invalid.issues.single.field, 'Importe');
    expect(invalid.issues.single.reason, contains('Tabla 1 · fila física 12'));
    for (final bytes in [
      <int>[],
      [0xd0, 0xcf, 0x11, 0xe0],
      [0x50, 0x4b, 0x03, 0x04],
    ]) {
      expect(reader.read(bytes).issues, isNotEmpty);
    }
    final wrong = ImportFile.fromBytes(
      bytes: bankFixture(),
      fingerprint: const Sha256ImportFingerprint(),
      source: ImportSource.historicalCsv,
      originalName: 'otro.csv',
    );
    expect(
      (await const OpenbankImportAdapter().interpret(wrong)).issues,
      isNotEmpty,
    );
  });
}
