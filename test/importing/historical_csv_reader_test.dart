import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/features/importing/data/historical_csv_reader.dart';
import 'package:myautofinance/features/importing/historical_csv.dart';

final _header = historicalCsvColumns.join(';');
const _real = '2026-01-03;Compra;-12.50;REAL;Alimentación;;;Cuenta principal;';
const _budget =
    '2026-01-01;Presupuesto;100.00;PRESUPUESTO;Vivienda;Alquiler;;;';
const _reader = HistoricalCsvReader();

HistoricalCsvReadResult _read(String rows) =>
    _reader.read(utf8.encode('$_header\n$rows'));

String _change(String row, int column, String value) {
  final fields = row.split(';');
  fields[column] = value;
  return fields.join(';');
}

void main() {
  test('plantilla EP-001: 48 presupuestos, 10 reales, signos y duplicados', () {
    final result = _reader.read(
      File('docs/ep-001/historico-ejemplo.csv').readAsBytesSync(),
    );
    expect(result.diagnostics, isEmpty);
    final real = result.records
        .where((r) => r.type == HistoricalCsvType.real)
        .toList();
    final budgets = result.records
        .where((r) => r.type == HistoricalCsvType.budget)
        .toList();
    expect(real, hasLength(10));
    expect(budgets, hasLength(48));
    expect(real.fold<int>(0, (sum, r) => sum + r.csvAmountCents), 232965);
    expect(
      real
          .where((r) => r.date.startsWith('2026-01'))
          .fold<int>(0, (sum, r) => sum + r.csvAmountCents),
      122975,
    );
    // El intermedio conserva el signo CSV; el futuro adaptador lo invertirá.
    expect(budgets.fold<int>(0, (sum, r) => sum + r.csvAmountCents), -1320000);
    expect(budgets.first.csvAmountCents, -300000);
    final coffees = real.where((r) => r.concept == 'Café').toList();
    expect(coffees.map((r) => r.sourceOrdinal), [54, 55]);
    expect(coffees.map((r) => r.csvAmountCents), [-1000, -1000]);
    expect(
      result.records.map((r) => r.sourceOrdinal),
      List.generate(58, (i) => i + 2),
    );
  });

  for (final ending in ['\n', '\r\n']) {
    for (final bom in [false, true]) {
      for (final trailing in [false, true]) {
        test('UTF-8 BOM=$bom CRLF=${ending.length == 2} final=$trailing', () {
          final text =
              '$_header$ending$_real$ending$_budget${trailing ? ending : ''}';
          final result = _reader.read([
            if (bom) ...[0xef, 0xbb, 0xbf],
            ...utf8.encode(text),
          ]);
          expect(result.isValid, isTrue);
          expect(result.records.map((r) => r.sourceOrdinal), [2, 3]);
        });
      }
    }
  }

  test('entrecomillado, ;, comillas duplicadas y multilinea conservada', () {
    final text =
        '$_header\r\n2026-01-03;" Compra; ""especial""\r\nsegunda línea ";-0.01;rEaL;" Ocio ";;;" Cuenta principal ";" Necesario \ntexto "\r\n$_real';
    final result = _reader.read(utf8.encode(text));
    expect(result.isValid, isTrue);
    final first = result.records.first;
    expect(first.concept, 'Compra; "especial"\r\nsegunda línea');
    expect(
      first.originalFields[1].value,
      ' Compra; "especial"\r\nsegunda línea ',
    );
    expect(first.discretion, 'Necesario \ntexto');
    expect(first.originalFields[8].value, ' Necesario \ntexto ');
    expect(first.accountName, 'Cuenta principal');
    expect(first.categoryPath, ['Ocio']);
    expect(first.originalFields.map((f) => f.name), historicalCsvColumns);
    expect(first.originalFields[2].physicalLine, 3);
    expect(result.records.last.sourceOrdinal, 3);
    expect(result.records.last.physicalLine, 5);
    expect(first.csvAmountCents, -1);
  });

  test('espacios externos tratados, grafía e interiores conservados', () {
    final result = _read(
      ' 2026-01-01 ; Presupuesto ; -0.00 ; presupuesto ; InGrEsOs ; Sala  rio ; ; ; Texto libre ',
    );
    final record = result.records.single;
    expect(record.date, '2026-01-01');
    expect(record.type, HistoricalCsvType.budget);
    expect(record.csvAmountCents, 0);
    expect(record.originalFields[2].value, ' -0.00 ');
    expect(record.categoryPath, ['InGrEsOs', 'Sala  rio']);
    expect(record.accountName, isEmpty);
    expect(record.discretion, 'Texto libre');
    expect(() => record.categoryPath.add('otro'), throwsUnsupportedError);
    expect(() => record.originalFields.clear(), throwsUnsupportedError);
    expect(() => result.records.clear(), throwsUnsupportedError);
    expect(() => result.diagnostics.clear(), throwsUnsupportedError);
  });

  for (final invalid in [
    [0xc3, 0x28],
    [0xff],
    [0xc0, 0xaf],
    [0xed, 0xa0, 0x80],
    [0xf4, 0x90, 0x80, 0x80],
    [0xe2, 0x82],
  ]) {
    test('rechaza bytes UTF-8 $invalid en todo el archivo', () {
      final result = _reader.read([
        ...utf8.encode('$_header\n$_real\n'),
        ...invalid,
      ]);
      expect(result.records, isEmpty);
      expect(
        result.diagnostics.single.code,
        HistoricalCsvIssueCode.invalidUtf8,
      );
      expect(result.diagnostics.single.sourceOrdinal, isNull);
      expect(result.diagnostics.single.byteOffset, isNotNull);
    });
  }

  for (final header in [
    '',
    '$_header;',
    _header.replaceAll(';', ','),
    _header.toUpperCase(),
    ' $_header',
    _header.replaceFirst('fecha;concepto', 'concepto;fecha'),
    _header.replaceFirst('importe_eur;', ''),
  ]) {
    test('rechaza cabecera exacta: $header', () {
      final result = _reader.read(utf8.encode('$header\n$_real'));
      expect(result.records, isEmpty);
      expect(
        result.diagnostics.single.code,
        HistoricalCsvIssueCode.invalidHeader,
      );
      expect(result.diagnostics.single.sourceOrdinal, 1);
    });
  }

  test('archivo vacío falla; cabecera sola no inventa registros', () {
    expect(
      _reader.read([]).diagnostics.single.code,
      HistoricalCsvIssueCode.invalidHeader,
    );
    expect(_reader.read([0xef, 0xbb, 0xbf]).isValid, isFalse);
    for (final suffix in ['', '\n', '\r\n']) {
      final result = _reader.read(utf8.encode('$_header$suffix'));
      expect(result.isValid, isTrue);
      expect(result.records, isEmpty);
    }
  });

  for (final row in ['$_real;', _real.substring(0, _real.length - 1)]) {
    test('columnas incorrectas bloquean el archivo: $row', () {
      final result = _read('$_real\n$row\n$_budget');
      expect(result.records, isEmpty);
      expect(
        result.diagnostics.single.code,
        HistoricalCsvIssueCode.invalidColumnCount,
      );
      expect(result.diagnostics.single.sourceOrdinal, 3);
    });
  }

  for (final row in ['', '   ', '\r\n']) {
    test('fila vacía intermedia bloquea todo: ${jsonEncode(row)}', () {
      final result = _read('$_real\n$row\n$_budget');
      expect(result.records, isEmpty);
      expect(result.diagnostics.first.code, HistoricalCsvIssueCode.emptyRecord);
      expect(result.diagnostics.first.sourceOrdinal, 3);
      expect(result.diagnostics.first.physicalLine, 3);
    });
  }
  test('segundo salto final sí es un registro vacío', () {
    final result = _read('$_real\n\n');
    expect(result.diagnostics.single.code, HistoricalCsvIssueCode.emptyRecord);
    expect(result.records, isEmpty);
  });

  for (final concept in [
    '"sin cerrar',
    'comilla"suelta',
    '"cerrado"texto',
    '"cerrado" ',
  ]) {
    test('comillas mal formadas no reconstruyen filas: $concept', () {
      final result = _read(
        '$_real\n2026-01-03;$concept;-1.00;REAL;;;;Cuenta;\n$_real',
      );
      expect(result.records, isEmpty);
      expect(
        result.diagnostics.single.code,
        HistoricalCsvIssueCode.invalidQuoting,
      );
      expect(result.diagnostics.single.sourceOrdinal, 3);
      expect(result.diagnostics.single.field, 'concepto');
    });
  }
  test('saltos CR aislados rechazados incluso dentro de comillas', () {
    for (final rows in [
      '$_real\r$_budget',
      '2026-01-03;"a\rb";-1.00;REAL;;;;Cuenta;',
    ]) {
      expect(
        _read(rows).diagnostics.single.code,
        HistoricalCsvIssueCode.invalidLineEnding,
      );
    }
  });

  test(
    'diagnóstico después de multilinea usa ordinal lógico y línea de campo',
    () {
      final result = _read(
        '2026-01-03;"a\nb";-1.00;REAL;;;;Cuenta;\n2026-01-03;"c\nd";mal;REAL;;;;Cuenta;',
      );
      final error = result.diagnostics.single;
      expect(error.sourceOrdinal, 3);
      expect(error.physicalLine, 5);
      expect(error.field, 'importe_eur');
      expect(error.reason, isNotEmpty);
      expect(result.records, isEmpty);
    },
  );

  for (final date in [
    '2026-02-30',
    '2026-02-29',
    '1900-02-29',
    '2026-04-31',
    '0000-01-01',
    '2026-00-01',
    '2026-13-01',
    '2026-01-00',
    '2026-01-32',
    '2026-1-03',
    '2026-01-03T00:00:00',
    '03/01/2026',
    '10000-01-01',
  ]) {
    test('rechaza fecha $date', () {
      final result = _read(_change(_real, 0, date));
      expect(
        result.diagnostics.single.code,
        HistoricalCsvIssueCode.invalidDate,
      );
      expect(result.diagnostics.single.field, 'fecha');
    });
  }
  for (final date in ['0001-01-01', '2000-02-29', '2024-02-29', '9999-12-31']) {
    test('acepta fecha civil $date', () {
      expect(_read(_change(_real, 0, date)).records.single.date, date);
    });
  }

  final fieldCases = <(String, int, String, HistoricalCsvIssueCode)>[
    (_budget, 0, '2026-01-15', HistoricalCsvIssueCode.invalidBudgetDay),
    (_real, 1, ' ', HistoricalCsvIssueCode.requiredField),
    (_budget, 1, '', HistoricalCsvIssueCode.requiredField),
    (_real, 3, 'OTRO', HistoricalCsvIssueCode.invalidType),
    (_budget, 4, '', HistoricalCsvIssueCode.requiredField),
    (_real, 7, ' ', HistoricalCsvIssueCode.requiredField),
    (_budget, 7, 'Cuenta', HistoricalCsvIssueCode.unexpectedAccount),
    (_real, 4, '', HistoricalCsvIssueCode.invalidHierarchy),
    (_real, 5, '', HistoricalCsvIssueCode.invalidHierarchy),
  ];
  for (var i = 0; i < fieldCases.length; i++) {
    test('regla de campo $i', () {
      final (base, column, value, code) = fieldCases[i];
      var row = _change(base, column, value);
      if (i == 7) row = _change(row, 5, 'Subcategoría');
      if (i == 8) row = _change(row, 6, 'Tercer nivel');
      final result = _read(row);
      expect(result.records, isEmpty);
      expect(result.diagnostics.map((e) => e.code), contains(code));
    });
  }

  for (final amount in [
    '1',
    '1.0',
    '1.000',
    '1,00',
    '1,000.00',
    '1.000,00',
    '€1.00',
    '1.00 EUR',
    '+1.00',
    '1e2',
    '.01',
    '--1.00',
    '−1.00',
    'NaN',
  ]) {
    test('rechaza importe $amount', () {
      final error = _read(_change(_real, 2, amount)).diagnostics.single;
      expect(error.code, HistoricalCsvIssueCode.invalidAmount);
      expect(error.field, 'importe_eur');
    });
  }
  for (final amount in ['0.00', '-0.00']) {
    test('cero $amount solo permitido en presupuesto', () {
      expect(
        _read(_change(_real, 2, amount)).diagnostics.single.code,
        HistoricalCsvIssueCode.zeroMovement,
      );
      final record = _read(_change(_budget, 2, amount)).records.single;
      expect(record.csvAmountCents, 0);
      expect(record.originalFields[2].value, amount);
    });
  }
  test('céntimos exactos con límites int64 y cero inicial', () {
    for (final (text, cents) in <(String, int)>[
      ('0.01', 1),
      ('0000012.50', 1250),
      ('-0.29', -29),
      ('92233720368547758.07', 9223372036854775807),
      ('-92233720368547758.08', -9223372036854775808),
    ]) {
      expect(
        _read(_change(_real, 2, text)).records.single.csvAmountCents,
        cents,
      );
    }
    for (final amount in [
      '92233720368547758.08',
      '-92233720368547758.09',
      '999999999999999999999999999999999.00',
    ]) {
      expect(
        _read(_change(_real, 2, amount)).diagnostics.single.code,
        HistoricalCsvIssueCode.amountOutOfRange,
      );
    }
    expect(
      _read(_change(_budget, 2, '-92233720368547758.08'))
          .diagnostics
          .single
          .code,
      HistoricalCsvIssueCode.amountOutOfRange,
    );
    expect(
      _read(_change(_budget, 2, '-92233720368547758.07'))
          .records
          .single
          .csvAmountCents,
      -9223372036854775807,
    );
  });

  test(
    'REAL sin clasificar y positivo en Ahorro conserva referencia y signo',
    () {
      var row = _change(_real, 4, '');
      expect(_read(row).records.single.categoryPath, isEmpty);
      row = _change(_change(_real, 4, 'Ahorro'), 2, '7.00');
      final record = _read(row).records.single;
      expect(record.categoryPath, ['Ahorro']);
      expect(record.csvAmountCents, 700);
    },
  );
  test('recorre errores de campos de todas las filas y bloquea lote completo', () {
    final result = _read(
      '$_real\n2026-02-30; ;mal;OTRO;;Sub;;Cuenta;\n${_change(_budget, 7, 'Cuenta')}',
    );
    expect(result.records, isEmpty);
    expect(result.diagnostics.map((e) => e.sourceOrdinal).toSet(), {3, 4});
    expect(result.diagnostics.where((e) => e.sourceOrdinal == 3), hasLength(5));
    expect(
      result.diagnostics.map((e) => e.field),
      containsAll([
        'fecha',
        'concepto',
        'importe_eur',
        'tipo',
        'subcategoria',
        'cuenta_origen',
      ]),
    );
  });
}
