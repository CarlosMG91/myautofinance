import 'dart:convert';

import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';

/// Lector determinista de fixtures JSON en memoria. Vive bajo test/ para que
/// nunca forme parte del grafo de producción ni pretenda ser CSV/XLS real.
final class SyntheticImportAdapter implements ImportAdapter {
  const SyntheticImportAdapter(this.source);

  @override
  final ImportSource source;

  @override
  Future<ImportInterpretation> interpret(ImportFile file) async {
    if (file.source != source) {
      return ImportInterpretation(
        formatVersion: 'synthetic-json-1',
        issues: const [
          ImportIssue(
            code: ImportIssueCode.invalidFile,
            reason: 'El fixture no corresponde al origen declarado.',
          ),
        ],
      );
    }
    final rows = <InterpretedImportRow>[];
    final issues = <ImportIssue>[];
    try {
      final document = jsonDecode(utf8.decode(file.bytes));
      if (document is! Map<String, dynamic> || document['rows'] is! List) {
        throw const FormatException('Se esperaba un objeto con "rows".');
      }
      for (final item in document['rows'] as List) {
        final ordinal = item is Map && item['ordinal'] is int
            ? item['ordinal'] as int
            : null;
        try {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('La fila no es un objeto.');
          }
          final kind = item['kind'];
          final concept = item['concept'];
          final cents = item['cents'];
          final fields = _fields(item['fields']);
          if (concept is! String || cents is! int) {
            throw const FormatException('Concepto o importe inválido.');
          }
          final rowOrdinal = item['ordinal'];
          if (rowOrdinal is! int) {
            throw const FormatException('Ordinal inválido.');
          }
          if (kind == 'REAL') {
            final date = item['date'];
            if (date is! String) throw const FormatException('Falta fecha.');
            final account = item['account'];
            if (account == null && source != ImportSource.bankXls) {
              throw const FormatException('Falta cuenta real.');
            }
            final dateParts = date.split('-');
            if (dateParts.length != 3) {
              throw const FormatException('Fecha inválida.');
            }
            final category = _path(item['category']);
            rows.add(
              InterpretedMovement(
                sourceOrdinal: rowOrdinal,
                originalFields: fields,
                concept: concept,
                amount: ImportAmount.economic(cents),
                valueDate: ValueDate(
                  int.parse(dateParts[0]),
                  int.parse(dateParts[1]),
                  int.parse(dateParts[2]),
                ),
                account: account == null
                    ? const ImportAccountReference.selectedAccount()
                    : ImportAccountReference.named(account as String),
                category: category == null
                    ? null
                    : ImportCategoryReference(category),
                discretion: item['discretion'] as String?,
              ),
            );
          } else if (kind == 'PRESUPUESTO' &&
              source == ImportSource.historicalCsv) {
            final month = item['month'];
            if (month is! String) throw const FormatException('Falta mes.');
            final category = _path(item['category']);
            if (category == null) {
              throw const FormatException('Falta categoría presupuestaria.');
            }
            final parts = month.split('-');
            if (parts.length != 2) throw const FormatException('Mes inválido.');
            rows.add(
              InterpretedBudget(
                sourceOrdinal: rowOrdinal,
                originalFields: fields,
                concept: concept,
                amount: ImportAmount.historicalBudget(cents),
                month: BudgetMonth(int.parse(parts[0]), int.parse(parts[1])),
                category: ImportCategoryReference(category),
                discretion: item['discretion'] as String?,
              ),
            );
          } else {
            throw const FormatException('Tipo no admitido para este origen.');
          }
        } catch (error) {
          issues.add(
            ImportIssue(
              code: ImportIssueCode.invalidField,
              sourceOrdinal: ordinal,
              reason: 'Fila sintética inválida: $error',
            ),
          );
        }
      }
    } on Object catch (error) {
      issues.add(
        ImportIssue(
          code: ImportIssueCode.invalidFile,
          reason: 'Fixture sintético ilegible: $error',
        ),
      );
    }
    return ImportInterpretation(
      formatVersion: 'synthetic-json-1',
      rows: rows,
      issues: issues,
    );
  }

  static List<ImportOriginalField> _fields(Object? value) {
    if (value == null) return const [];
    if (value is! List) throw const FormatException('Campos inválidos.');
    return value.map((field) {
      if (field is! Map ||
          field['name'] is! String ||
          field['value'] is! String) {
        throw const FormatException('Campo original inválido.');
      }
      return ImportOriginalField(
        field['name'] as String,
        field['value'] as String,
      );
    }).toList();
  }

  static List<String>? _path(Object? value) {
    if (value == null) return null;
    if (value is! List || value.any((part) => part is! String)) {
      throw const FormatException('Ruta de categoría inválida.');
    }
    return value.cast<String>();
  }
}
