import 'dart:isolate';

import '../features/importing/data/openbank_import_adapter.dart';
import '../features/importing/data/sha256_import_fingerprint.dart';
import '../features/importing/importing.dart';
import '../features/importing/presentation/import_controller.dart';
import 'openbank_selector_factory.dart';

ImportController createOpenbankImportController(
  ImportServicesLoader load, {
  LocalFileSelector? selector,
}) => ImportController(
  load,
  bankSelector: selector ?? createOpenbankSelector(),
  prepareBank: prepareOpenbankFile,
  bankAdapter: const BackgroundOpenbankAdapter(),
);

Future<ImportFile> prepareOpenbankFile(LocalFileSelected selected) {
  final bytes = selected.bytes;
  final name = selected.name;
  return Isolate.run(
    () => ImportFile.fromBytes(
      bytes: bytes,
      fingerprint: const Sha256ImportFingerprint(),
      source: ImportSource.bankXls,
      originalName: name,
    ),
  );
}

final class BackgroundOpenbankAdapter implements ImportAdapter {
  const BackgroundOpenbankAdapter();
  @override
  ImportSource get source => ImportSource.bankXls;
  @override
  Future<ImportInterpretation> interpret(ImportFile file) =>
      Isolate.run(() => const OpenbankImportAdapter().interpret(file));
}
