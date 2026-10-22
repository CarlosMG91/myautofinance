import '../../movements/movements.dart';
import '../importing.dart';
import '../domain/openbank.dart';
import 'openbank_reader.dart';

final class OpenbankImportAdapter implements ImportAdapter {
  const OpenbankImportAdapter({this.reader = const OpenbankReader()});
  final OpenbankReader reader;

  @override
  ImportSource get source => ImportSource.bankXls;

  @override
  Future<ImportInterpretation> interpret(ImportFile file) async {
    if (file.source != source) {
      return ImportInterpretation(
        formatVersion: openbankFormatVersion,
        issues: const [
          ImportIssue(
            code: ImportIssueCode.invalidFile,
            reason: 'El lector Openbank requiere el origen bancario.',
          ),
        ],
      );
    }
    final read = reader.read(file.bytes);
    return ImportInterpretation(
      formatVersion: openbankFormatVersion,
      issues: read.issues,
      rows: [
        for (final r in read.records)
          InterpretedMovement(
            sourceOrdinal: r.physicalRow,
            originalFields: r.originalFields,
            concept: r.concept,
            amount: ImportAmount.economic(r.amountCents),
            valueDate: ValueDate.parse(r.valueDate),
            account: const ImportAccountReference.selectedAccount(),
          ),
      ],
    );
  }
}
