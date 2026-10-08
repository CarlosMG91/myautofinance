import '../../budget/budget.dart';
import '../../movements/movements.dart';
import '../historical_csv.dart';
import '../importing.dart';
import 'historical_csv_reader.dart';

/// Convierte el lector puro al contrato común, sin catálogos ni persistencia.
final class HistoricalCsvImportAdapter implements ImportAdapter {
  const HistoricalCsvImportAdapter({this.reader = const HistoricalCsvReader()});

  final HistoricalCsvReader reader;

  @override
  ImportSource get source => ImportSource.historicalCsv;

  @override
  Future<ImportInterpretation> interpret(ImportFile file) async {
    if (file.source != source) {
      return ImportInterpretation(
        formatVersion: historicalCsvVersion,
        issues: const [
          ImportIssue(
            code: ImportIssueCode.invalidFile,
            reason:
                'El adaptador CSV histórico requiere el origen historicalCsv.',
          ),
        ],
      );
    }
    final result = reader.read(file.bytes);
    return ImportInterpretation(
      formatVersion: historicalCsvVersion,
      // El lector entrega cero registros ante cualquier error del archivo.
      issues: result.diagnostics.map(_issue).toList(),
      rows: result.records.map(_row).toList(),
    );
  }

  InterpretedImportRow _row(HistoricalCsvRecord record) {
    final fields = [
      for (final field in record.originalFields)
        ImportOriginalField(field.name, field.value),
    ];
    final category = record.categoryPath.isEmpty
        ? null
        : ImportCategoryReference(record.categoryPath);
    return switch (record.type) {
      HistoricalCsvType.real => InterpretedMovement(
        sourceOrdinal: record.sourceOrdinal,
        originalFields: fields,
        concept: record.concept,
        discretion: record.discretion,
        amount: ImportAmount.economic(record.csvAmountCents),
        valueDate: ValueDate.parse(record.date),
        account: ImportAccountReference.named(record.accountName),
        category: category,
      ),
      HistoricalCsvType.budget => InterpretedBudget(
        sourceOrdinal: record.sourceOrdinal,
        originalFields: fields,
        concept: record.concept,
        discretion: record.discretion,
        amount: ImportAmount.historicalBudget(record.csvAmountCents),
        month: BudgetMonth.parse(record.date),
        category: category!,
      ),
    };
  }

  ImportIssue _issue(HistoricalCsvDiagnostic diagnostic) => ImportIssue(
    code: switch (diagnostic.code) {
      HistoricalCsvIssueCode.invalidUtf8 ||
      HistoricalCsvIssueCode.invalidHeader ||
      HistoricalCsvIssueCode.invalidColumnCount ||
      HistoricalCsvIssueCode.invalidQuoting ||
      HistoricalCsvIssueCode.invalidLineEnding ||
      HistoricalCsvIssueCode.emptyRecord => ImportIssueCode.invalidFile,
      HistoricalCsvIssueCode.invalidDate ||
      HistoricalCsvIssueCode.invalidBudgetDay ||
      HistoricalCsvIssueCode.invalidType ||
      HistoricalCsvIssueCode.requiredField ||
      HistoricalCsvIssueCode.invalidHierarchy ||
      HistoricalCsvIssueCode.unexpectedAccount ||
      HistoricalCsvIssueCode.invalidAmount ||
      HistoricalCsvIssueCode.amountOutOfRange ||
      HistoricalCsvIssueCode.zeroMovement => ImportIssueCode.invalidField,
    },
    sourceOrdinal: diagnostic.sourceOrdinal,
    field: diagnostic.field,
    reason:
        '${diagnostic.reason}'
        '${diagnostic.physicalLine == null ? '' : ' · línea física ${diagnostic.physicalLine}'}'
        '${diagnostic.byteOffset == null ? '' : ' · byte ${diagnostic.byteOffset}'}',
  );
}
