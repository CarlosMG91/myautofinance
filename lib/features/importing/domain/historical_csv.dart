const historicalCsvVersion = '1';

const historicalCsvColumns = <String>[
  'fecha',
  'concepto',
  'importe_eur',
  'tipo',
  'categoria',
  'subcategoria',
  'subsubcategoria',
  'cuenta_origen',
  'discrecionalidad',
];

enum HistoricalCsvType { real, budget }

enum HistoricalCsvIssueCode {
  invalidUtf8,
  invalidHeader,
  invalidColumnCount,
  invalidQuoting,
  invalidLineEnding,
  emptyRecord,
  invalidDate,
  invalidBudgetDay,
  invalidType,
  requiredField,
  invalidHierarchy,
  unexpectedAccount,
  invalidAmount,
  amountOutOfRange,
  zeroMovement,
}

/// El ordinal identifica el registro lógico (cabecera = 1), no la línea.
final class HistoricalCsvDiagnostic {
  const HistoricalCsvDiagnostic({
    required this.code,
    required this.reason,
    this.sourceOrdinal,
    this.field,
    this.physicalLine,
    this.byteOffset,
  });

  final HistoricalCsvIssueCode code;
  final String reason;
  final int? sourceOrdinal;
  final String? field;
  final int? physicalLine;
  final int? byteOffset;
}

/// Valores CSV desentrecomillados, con espacios y saltos originales intactos.
final class HistoricalCsvField {
  const HistoricalCsvField(this.name, this.value, this.physicalLine);
  final String name, value;
  final int physicalLine;
}

/// Intermedio sin UUID, marca de ingreso, asignaciones ni signo normalizado.
final class HistoricalCsvRecord {
  HistoricalCsvRecord({
    required this.sourceOrdinal,
    required this.physicalLine,
    required List<HistoricalCsvField> originalFields,
    required this.date,
    required this.concept,
    required this.csvAmountCents,
    required this.type,
    required List<String> categoryPath,
    required this.accountName,
    required this.discretion,
  }) : originalFields = List.unmodifiable(originalFields),
       categoryPath = List.unmodifiable(categoryPath);

  final int sourceOrdinal, physicalLine;
  final List<HistoricalCsvField> originalFields;

  /// Fecha ISO civil validada, sin conversión de zona horaria.
  final String date;
  final String concept;

  /// El adaptador invierte PRESUPUESTO una sola vez. REAL conserva su signo.
  final int csvAmountCents;
  final HistoricalCsvType type;
  final List<String> categoryPath;

  /// Vacía para PRESUPUESTO; obligatoria para REAL.
  final String accountName;
  final String discretion;
}

final class HistoricalCsvReadResult {
  HistoricalCsvReadResult({
    required List<HistoricalCsvRecord> records,
    required List<HistoricalCsvDiagnostic> diagnostics,
  }) : diagnostics = List.unmodifiable(diagnostics),
       records = List.unmodifiable(
         diagnostics.isEmpty ? records : <HistoricalCsvRecord>[],
       );

  /// Nunca expone un subconjunto importable si el archivo tiene errores.
  final List<HistoricalCsvRecord> records;
  final List<HistoricalCsvDiagnostic> diagnostics;
  bool get isValid => diagnostics.isEmpty;
}
