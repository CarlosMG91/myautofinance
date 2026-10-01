import '../../../core/persistence/unit_of_work.dart';

final class LocalBackup {
  const LocalBackup({required this.path, required this.state});
  final String path;
  final DatasetState state;
}

/// Una copia nueva validada; no sustituye la base ni transfiere archivos.
abstract interface class LocalBackupSource {
  Future<LocalBackup> createConsistentBackup();
}
