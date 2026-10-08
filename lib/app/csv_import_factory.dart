import 'dart:isolate';

import '../features/importing/data/historical_csv_import_adapter.dart';
import '../features/importing/data/sha256_import_fingerprint.dart';
import '../features/importing/importing.dart';
import '../features/importing/presentation/import_controller.dart';
import 'local_csv_selector_factory.dart';

ImportController createCsvImportController(
  ImportServicesLoader load, {
  LocalCsvSelector? selector,
}) => ImportController(
  load,
  csvSelector: selector ?? createLocalCsvSelector(),
  prepareCsv: prepareHistoricalCsvFile,
  csvAdapter: const BackgroundHistoricalCsvAdapter(),
);

Future<ImportFile> prepareHistoricalCsvFile(LocalCsvSelected selected) {
  final bytes = selected.bytes;
  final name = selected.name;
  return Isolate.run(
    () => ImportFile.fromBytes(
      bytes: bytes,
      fingerprint: const Sha256ImportFingerprint(),
      source: ImportSource.historicalCsv,
      originalName: name,
    ),
  );
}

/// SHA y parseo se ejecutan fuera del hilo de interfaz en ambas plataformas.
final class BackgroundHistoricalCsvAdapter implements ImportAdapter {
  const BackgroundHistoricalCsvAdapter();
  @override
  ImportSource get source => ImportSource.historicalCsv;
  @override
  Future<ImportInterpretation> interpret(ImportFile file) =>
      Isolate.run(() => const HistoricalCsvImportAdapter().interpret(file));
}
