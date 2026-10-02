import 'package:flutter/foundation.dart';

import '../domain/local_backup_catalog.dart';
import '../domain/local_backup_creation.dart';
import '../domain/local_restore.dart';
import '../domain/local_restore_candidate.dart';

/// Estado de una instalación. No recibe clientes remotos ni rutas externas.
class LocalBackupController extends ChangeNotifier {
  LocalBackupController({
    required this.catalog,
    required this.creator,
    required this.restorer,
    this.activeAvailable = true,
    this.startupMessage,
    this.recoveryBlocked = false,
    this.retryStartup,
  });

  final LocalBackupCatalog catalog;
  final LocalBackupCreator creator;
  final LocalRestorer restorer;
  final Future<bool> Function()? retryStartup;
  bool activeAvailable;
  bool recoveryBlocked;
  String? startupMessage;
  LocalBackupCatalogListing? listing;
  LocalRestoreResult? restoreResult;
  String? message;
  String? error;
  String? progress;
  bool get busy => progress != null;

  static const storageMessage =
      'No se pudo acceder o guardar en el almacenamiento local. '
      'Comprueba los permisos y el espacio libre del dispositivo y reintenta. '
      'No se han eliminado copias manuales para liberar espacio.';

  Future<void> _run(String phase, Future<void> Function() action) async {
    if (busy) return;
    progress = phase;
    error = null;
    message = null;
    notifyListeners();
    try {
      await action();
    } on LocalBackupFailure catch (failure) {
      if (failure.code == LocalBackupFailureCode.recoveryRequired) {
        activeAvailable = false;
        recoveryBlocked = true;
      }
      error = switch (failure.code) {
        LocalBackupFailureCode.storageFailure => storageMessage,
        LocalBackupFailureCode.operationInProgress => 'Hay otra operación de copias locales en curso. Reintenta al terminar.',
        LocalBackupFailureCode.recoveryRequired =>
          'Hay una recuperación pendiente. Reinicia la app antes de continuar.',
        LocalBackupFailureCode.invalidSnapshot => 'No se pudo comprobar la copia SQLite. Se conserva el estado anterior.',
        LocalBackupFailureCode.invalidMetadata => 'Los metadatos de la copia no son válidos. Se conserva el estado anterior.',
        LocalBackupFailureCode.incompatibleCatalog =>
          'El catálogo requiere revisión o una versión compatible de la app.',
        LocalBackupFailureCode.counterExhausted =>
          'No se pueden registrar más copias en este catálogo.',
      };
    } catch (_) {
      error = storageMessage;
    } finally {
      progress = null;
      notifyListeners();
    }
  }

  Future<void> refresh() => _run('Leyendo catálogo local…', _read);

  Future<void> _read() async {
    final LocalBackupCatalogListing next;
    try {
      next = await catalog.read();
    } catch (_) {
      listing = null;
      rethrow;
    }
    listing = next;
    if (next.incidents.any(
      (incident) => incident.issue == LocalBackupCatalogIssue.unresolvedRestore,
    )) {
      activeAvailable = false;
      recoveryBlocked = true;
      startupMessage = 'Hay un intercambio pendiente. Reinicia la app para resolverlo antes de abrir datos.';
    }
    if (next.status == LocalBackupCatalogStatus.unavailable) {
      error =
          'No se pudo leer el catálogo. Esto no significa que no haya copias. '
          '$storageMessage';
    } else if (next.status == LocalBackupCatalogStatus.incompatible) {
      error =
          'El catálogo está dañado o tiene un formato incompatible. '
          'Se conservan los archivos. Usa una versión compatible de Autofinance.';
    }
  }

  Future<void> create() async {
    if (!activeAvailable || recoveryBlocked) return;
    await _run('Creando, comprobando y registrando copia local…', () async {
      final copy = await creator.createManual();
      message = 'Copia manual creada, comprobada y registrada.';
      if (copy.cleanupPending) {
        message = '$message Quedan archivos temporales pendientes de limpieza.';
      }
      await _read();
    });
  }

  Future<void> restore(String id, {required bool confirmed}) async {
    if (!confirmed || recoveryBlocked) return;
    await _run('Validando, protegiendo el estado anterior y restaurando…', () async {
      final result = await restorer.restore(id, confirmed: true);
      restoreResult = result;
      switch (result.status) {
        case LocalRestoreStatus.restored:
          activeAvailable = true;
          startupMessage = null;
          message = 'Restauración completada. La base restaurada se ha abierto y comprobado.';
        case LocalRestoreStatus.cancelled:
          message = result.message;
        case LocalRestoreStatus.rejected:
          error =
              result.candidateIssue == LocalRestoreCandidateIssue.storageFailure
              ? storageMessage
              : result.message;
        case LocalRestoreStatus.rolledBack:
          activeAvailable = true;
          startupMessage = null;
          error = result.message;
        case LocalRestoreStatus.recoveryRequired:
          activeAvailable = false;
          recoveryBlocked = true;
          error =
              '${result.message} Reinicia la app para resolver el intercambio antes de abrir datos.';
      }
      await _read();
    });
  }

  Future<void> delete(String id) =>
      _run('Comprobando y eliminando copia…', () async {
        final result = await catalog.deleteExplicitly(id);
        if (result.deletedBackupIds.contains(id)) {
          message = 'Copia eliminada. La base activa no ha cambiado.';
        } else {
          error =
              'No se ha eliminado la copia. Se necesita otra copia válida '
              'y ninguna operación de recuperación pendiente. '
              'Comprueba también el acceso y el espacio del almacenamiento.';
        }
        await _read();
      });

  Future<void> retryOpen() =>
      _run('Resolviendo recuperación y abriendo base local…', () async {
        activeAvailable = await retryStartup!();
        if (activeAvailable) {
          startupMessage = null;
          recoveryBlocked = false;
          message = 'Base local abierta y comprobada.';
        } else {
          error =
              'La base sigue sin poder abrirse. Revisa una copia válida. '
              'Si hay un intercambio pendiente, reinicia la app.';
        }
        await _read();
      });
}
