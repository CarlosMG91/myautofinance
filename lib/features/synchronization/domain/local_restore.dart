import 'local_backup_creation.dart';
import 'local_backup.dart';
import 'local_restore_candidate.dart';

enum LocalRestoreStatus {
  cancelled,
  restored,
  rejected,
  rolledBack,
  recoveryRequired,
}

final class LocalRestoreResult {
  const LocalRestoreResult(
    this.status, {
    this.previousBackupId,
    this.candidateIssue,
    this.maintenancePending = false,
  });
  final LocalRestoreStatus status;
  final String? previousBackupId;
  final LocalRestoreCandidateIssue? candidateIssue;
  final bool maintenancePending;
  String get message => switch (status) {
    LocalRestoreStatus.cancelled =>
      'Restauración cancelada. No se han modificado archivos.',
    LocalRestoreStatus.restored =>
      'Copia restaurada y validada. El estado anterior sigue recuperable.',
    LocalRestoreStatus.rejected =>
      candidateIssue?.message ??
          'No se pudo iniciar la restauración. Se conserva el estado anterior.',
    LocalRestoreStatus.rolledBack => 'La restauración falló. Se ha restablecido y comprobado la base anterior.',
    LocalRestoreStatus.recoveryRequired => 'La restauración necesita recuperación. Los archivos se conservan y el acceso queda bloqueado.',
  };
}

abstract interface class LocalRestorer {
  /// La capa de presentación obtiene confirmación expresa antes de pasar true.
  /// false no abre bases, crea directorios, prepara candidatas ni toma respaldos.
  Future<LocalRestoreResult> restore(
    String backupId, {
    required bool confirmed,
  });
}

/// Propietario único de las conexiones. La exclusión drena escrituras admitidas,
/// rechaza nuevas y solo permite al coordinador abrir/capturar durante la acción.
abstract interface class LocalRestoreActiveDatabase
    implements LocalBackupSource {
  Future<T> exclusivelyForRestore<T>(Future<T> Function() action);
  Future<bool> canOpenExisting();
  Future<void> close();
  Future<LocalBackupImage> reopenAndValidate();
  void requireRecovery();
}
