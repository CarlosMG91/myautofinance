import 'interpreted_import.dart';

const openbankFormatVersion = 'openbank-xhtml-iso8859-1-v1';

/// Una tabla del exportador XHTML observado, con filas físicas desde 1.
final class OpenbankRecord {
  OpenbankRecord({
    required this.physicalRow,
    required this.valueDate,
    required this.concept,
    required this.amountCents,
    required List<ImportOriginalField> originalFields,
  }) : originalFields = List.unmodifiable(originalFields);

  final int physicalRow, amountCents;
  final String valueDate, concept;
  final List<ImportOriginalField> originalFields;
}

final class OpenbankReadResult {
  OpenbankReadResult({
    List<OpenbankRecord> records = const [],
    List<ImportIssue> issues = const [],
  }) : issues = List.unmodifiable(issues),
       records = List.unmodifiable(
         issues.isEmpty ? records : <OpenbankRecord>[],
       );

  final List<OpenbankRecord> records;
  final List<ImportIssue> issues;
}
