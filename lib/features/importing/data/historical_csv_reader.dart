import 'dart:convert';

import '../domain/historical_csv.dart';

/// UTF-8 y CSV estrictos. No lee disco, consulta catálogos ni escribe datos.
final class HistoricalCsvReader {
  const HistoricalCsvReader();

  HistoricalCsvReadResult read(List<int> bytes) {
    final diagnostics = <HistoricalCsvDiagnostic>[];
    final records = <HistoricalCsvRecord>[];
    String text;
    try {
      text = utf8.decode(bytes, allowMalformed: false);
    } on FormatException catch (error) {
      return HistoricalCsvReadResult(
        records: const [],
        diagnostics: [
          HistoricalCsvDiagnostic(
            code: HistoricalCsvIssueCode.invalidUtf8,
            reason: 'El archivo no contiene UTF-8 válido.',
            byteOffset: error.offset,
          ),
        ],
      );
    }
    final scanner = _CsvScanner(text);
    try {
      final header = scanner.next();
      if (header == null ||
          header.fields.length != historicalCsvColumns.length ||
          Iterable<int>.generate(historicalCsvColumns.length)
              .any((i) => header.fields[i].value != historicalCsvColumns[i])) {
        diagnostics.add(
          const HistoricalCsvDiagnostic(
            code: HistoricalCsvIssueCode.invalidHeader,
            reason: 'La cabecera debe contener las nueve columnas exactas en su orden.',
            sourceOrdinal: 1,
            physicalLine: 1,
          ),
        );
      } else {
        _CsvRow? row;
        while ((row = scanner.next()) != null) {
          _validate(row!, records, diagnostics);
        }
      }
    } on _CsvSyntaxFailure catch (error) {
      diagnostics.add(error.diagnostic);
    }
    return HistoricalCsvReadResult(records: records, diagnostics: diagnostics);
  }

  void _validate(
    _CsvRow row,
    List<HistoricalCsvRecord> records,
    List<HistoricalCsvDiagnostic> diagnostics,
  ) {
    void issue(HistoricalCsvIssueCode code, String reason, [int? column]) {
      diagnostics.add(
        HistoricalCsvDiagnostic(
          code: code,
          reason: reason,
          sourceOrdinal: row.ordinal,
          field: column == null ? null : historicalCsvColumns[column],
          physicalLine: column == null
              ? row.line
              : row.fields[column].physicalLine,
        ),
      );
    }

    if (row.blank) {
      issue(
        HistoricalCsvIssueCode.emptyRecord,
        'No se admiten registros vacíos.',
      );
      return;
    }
    if (row.fields.length != 9) {
      issue(
        HistoricalCsvIssueCode.invalidColumnCount,
        'Cada registro debe contener exactamente nueve campos.',
      );
      return;
    }
    final previousErrors = diagnostics.length;
    final values = row.fields.map((field) => field.value.trim()).toList();
    final type = switch (values[3].toUpperCase()) {
      'REAL' => HistoricalCsvType.real,
      'PRESUPUESTO' => HistoricalCsvType.budget,
      _ => null,
    };
    if (type == null) {
      issue(
        HistoricalCsvIssueCode.invalidType,
        'El tipo debe ser REAL o PRESUPUESTO.',
        3,
      );
    }
    final date = _date(values[0]);
    if (date == null) {
      issue(
        HistoricalCsvIssueCode.invalidDate,
        'La fecha debe ser AAAA-MM-DD y existir en el calendario (años 0001–9999).',
        0,
      );
    } else if (type == HistoricalCsvType.budget && date.day != 1) {
      issue(
        HistoricalCsvIssueCode.invalidBudgetDay,
        'Un presupuesto requiere el día 1 del mes.',
        0,
      );
    }
    if (values[1].isEmpty) {
      issue(
        HistoricalCsvIssueCode.requiredField,
        'El concepto es obligatorio.',
        1,
      );
    }
    if (values[4].isEmpty && type == HistoricalCsvType.budget) {
      issue(
        HistoricalCsvIssueCode.requiredField,
        'Un presupuesto requiere categoría.',
        4,
      );
    }
    if (values[5].isNotEmpty && values[4].isEmpty) {
      issue(
        HistoricalCsvIssueCode.invalidHierarchy,
        'Una subcategoría requiere categoría.',
        5,
      );
    }
    if (values[6].isNotEmpty && values[5].isEmpty) {
      issue(
        HistoricalCsvIssueCode.invalidHierarchy,
        'Una subsubcategoría requiere subcategoría.',
        6,
      );
    }
    if (type == HistoricalCsvType.real && values[7].isEmpty) {
      issue(
        HistoricalCsvIssueCode.requiredField,
        'Un movimiento REAL requiere cuenta.',
        7,
      );
    }
    if (type == HistoricalCsvType.budget && values[7].isNotEmpty) {
      issue(
        HistoricalCsvIssueCode.unexpectedAccount,
        'Un presupuesto no admite cuenta.',
        7,
      );
    }

    int? cents;
    if (!RegExp(r'^-?[0-9]+\.[0-9]{2}$').hasMatch(values[2])) {
      issue(
        HistoricalCsvIssueCode.invalidAmount,
        'El importe requiere punto y dos decimales, sin miles ni símbolo.',
        2,
      );
    } else {
      final exact = BigInt.parse(values[2].replaceAll('.', ''));
      final minimum = BigInt.parse('-9223372036854775808');
      final maximum = BigInt.parse('9223372036854775807');
      if (exact < minimum ||
          exact > maximum ||
          (type == HistoricalCsvType.budget && exact == minimum)) {
        issue(
          HistoricalCsvIssueCode.amountOutOfRange,
          'El importe CSV y su signo interno deben caber en céntimos int64.',
          2,
        );
      } else {
        cents = exact.toInt();
        if (type == HistoricalCsvType.real && cents == 0) {
          issue(
            HistoricalCsvIssueCode.zeroMovement,
            'Un movimiento REAL no admite importe cero.',
            2,
          );
        }
      }
    }
    if (diagnostics.length == previousErrors) {
      records.add(
        HistoricalCsvRecord(
          sourceOrdinal: row.ordinal,
          physicalLine: row.line,
          originalFields: row.fields,
          date: values[0],
          concept: values[1],
          csvAmountCents: cents!,
          type: type!,
          categoryPath: values
              .sublist(4, 7)
              .where((name) => name.isNotEmpty)
              .toList(),
          accountName: values[7],
          discretion: values[8],
        ),
      );
    }
  }

  DateTime? _date(String value) {
    if (!RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$').hasMatch(value)) return null;
    final year = int.parse(value.substring(0, 4));
    final month = int.parse(value.substring(5, 7));
    final day = int.parse(value.substring(8));
    if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime.utc(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }
}

final class _CsvRow {
  const _CsvRow(this.ordinal, this.line, this.fields, this.blank);
  final int ordinal, line;
  final List<HistoricalCsvField> fields;
  final bool blank;
}

final class _CsvSyntaxFailure implements Exception {
  const _CsvSyntaxFailure(this.diagnostic);
  final HistoricalCsvDiagnostic diagnostic;
}

/// Se detiene ante sintaxis ambigua: no intenta adivinar dónde acaba una fila.
final class _CsvScanner {
  _CsvScanner(this.text);
  final String text;
  int position = 0, line = 1, ordinal = 1;

  _CsvRow? next() {
    if (position == text.length) return null;
    final start = position;
    final startLine = line;
    final fields = <HistoricalCsvField>[];
    while (true) {
      final column = fields.length;
      final fieldLine = line;
      final value = StringBuffer();
      if (position < text.length && text[position] == '"') {
        position++;
        var closed = false;
        while (position < text.length) {
          final char = text[position];
          if (char == '"') {
            position++;
            if (position < text.length && text[position] == '"') {
              value.write('"');
              position++;
            } else {
              closed = true;
              break;
            }
          } else if (char == '\r' || char == '\n') {
            value.write(_newline(column));
          } else {
            value.write(char);
            position++;
          }
        }
        if (!closed) {
          _fail(
            HistoricalCsvIssueCode.invalidQuoting,
            'Campo entrecomillado sin cerrar.',
            column,
          );
        }
        if (position < text.length &&
            ![';', '\r', '\n'].contains(text[position])) {
          _fail(
            HistoricalCsvIssueCode.invalidQuoting,
            'Hay texto tras la comilla de cierre.',
            column,
          );
        }
      } else {
        while (position < text.length &&
            ![';', '\r', '\n'].contains(text[position])) {
          if (text[position] == '"') {
            _fail(
              HistoricalCsvIssueCode.invalidQuoting,
              'Las comillas solo se admiten al iniciar un campo entrecomillado.',
              column,
            );
          }
          value.write(text[position++]);
        }
      }
      fields.add(
        HistoricalCsvField(
          column < 9 ? historicalCsvColumns[column] : 'columna_${column + 1}',
          value.toString(),
          fieldLine,
        ),
      );
      if (position < text.length && text[position] == ';') {
        position++;
        continue;
      }
      final blank = text.substring(start, position).trim().isEmpty;
      if (position < text.length) _newline(column);
      return _CsvRow(ordinal++, startLine, fields, blank);
    }
  }

  String _newline(int column) {
    if (text[position] == '\r') {
      if (position + 1 == text.length || text[position + 1] != '\n') {
        _fail(
          HistoricalCsvIssueCode.invalidLineEnding,
          'Solo se admiten saltos LF o CRLF.',
          column,
        );
      }
      position += 2;
      line++;
      return '\r\n';
    }
    position++;
    line++;
    return '\n';
  }

  Never _fail(HistoricalCsvIssueCode code, String reason, int column) =>
      throw _CsvSyntaxFailure(
        HistoricalCsvDiagnostic(
          code: code,
          reason: reason,
          sourceOrdinal: ordinal,
          field: column < 9 ? historicalCsvColumns[column] : null,
          physicalLine: line,
        ),
      );
}
