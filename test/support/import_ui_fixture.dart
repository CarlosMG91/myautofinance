import 'package:myautofinance/features/importing/importing.dart';

/// Adaptador inyectable exclusivo de pruebas; no está incluido en lib/.
class SyntheticUiAdapter implements ImportAdapter {
  SyntheticUiAdapter(this.rows, {this.issues = const []});
  final List<InterpretedImportRow> rows;
  final List<ImportIssue> issues;
  @override
  ImportSource get source => ImportSource.historicalCsv;
  @override
  Future<ImportInterpretation> interpret(ImportFile file) async =>
      ImportInterpretation(
        formatVersion: 'synthetic-ui-112',
        rows: rows,
        issues: issues,
      );
}
