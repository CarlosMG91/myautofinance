import 'drive_access.dart';
import 'drive_metadata.dart';

enum DriveFolderStatus {
  found,
  created,
  notFound,
  missingOrInaccessible,
  moved,
  invalidIdentity,
  ambiguous,
  creationUnconfirmed,
}

/// Solo acredita carpeta, nunca existencia ni validez de una copia SQLite.
final class DriveFolderResult {
  DriveFolderResult._(
    this.status, {
    this.folder,
    List<String> candidateIds = const [],
  }) : candidateIds = List.unmodifiable(candidateIds);

  final DriveFolderStatus status;
  final DriveFileMetadata? folder;
  final List<String> candidateIds;

  @override
  String toString() => 'DriveFolderResult(${status.name})';
}

/// Servicio común que el flujo manual compone una vez por instalación.
/// Construirlo no restaura sesión ni hace red. No autoriza ni renueva acceso.
/// Nunca adopta una carpeta solo por su nombre ni modifica recursos existentes.
final class DriveFolderLocator {
  DriveFolderLocator({required this._access, required this._metadata});

  final DriveAccess _access;
  final DriveMetadataClient _metadata;
  bool _busy = false;

  // Un POST sin confirmación puede terminar remotamente después del timeout.
  // No repetirlo a ciegas durante la vida de este servicio, aun si list está vacío.
  final _unconfirmedCreations = <String>{};

  /// Consulta expresa (por ejemplo, Descargar). Nunca crea una carpeta.
  Future<DriveFolderResult> findFolder() => _run(createIfMissing: false);

  /// Acción expresa que permite crear la carpeta si se acredita su ausencia.
  /// No llamar desde arranque, autorización ni una búsqueda automática.
  Future<DriveFolderResult> requestFolder() => _run(createIfMissing: true);

  DriveSession _session([String? expectedAccount]) {
    final session = _access.snapshot.session;
    if (session == null) {
      throw const DriveAccessFailure(DriveAccessIssue.credentialExpired);
    }
    if ((expectedAccount != null &&
            session.account.permissionId != expectedAccount) ||
        (session.folder != null &&
            session.folder!.accountId != session.account.permissionId)) {
      throw const DriveAccessFailure(DriveAccessIssue.accountChangeRequired);
    }
    if (session.grantedScopes.length != 1 ||
        !session.grantedScopes.contains(driveFileScope)) {
      throw const DriveAccessFailure(DriveAccessIssue.permissionDenied);
    }
    return session;
  }

  bool _hasIdentity(DriveFileMetadata folder) =>
      folder.mimeType == driveFolderMimeType &&
      driveAutofinanceFolderProperties.entries.every(
        (entry) => folder.appProperties[entry.key] == entry.value,
      );

  DriveFolderStatus? _invalid(DriveFileMetadata folder, String rootId) {
    if (folder.trashed) return DriveFolderStatus.missingOrInaccessible;
    if (!_hasIdentity(folder)) return DriveFolderStatus.invalidIdentity;
    if (folder.parents.length != 1 || folder.parents.single != rootId) {
      return DriveFolderStatus.moved;
    }
    return null;
  }

  Future<DriveFolderResult> _remember(
    String accountId,
    DriveFileMetadata folder,
    DriveFolderStatus status,
  ) async {
    final session = _session(accountId);
    if (session.folder?.folderId != folder.id) {
      final saved = await _access.rememberFolder(
        DriveFolderBinding(accountId: accountId, folderId: folder.id),
      );
      if (saved.issue != null ||
          saved.session?.folder?.folderId != folder.id ||
          saved.session?.folder?.accountId != accountId) {
        throw DriveAccessFailure(
          saved.issue ?? DriveAccessIssue.secureStorageFailure,
        );
      }
    }
    _session(accountId);
    _unconfirmedCreations.remove(accountId);
    return DriveFolderResult._(status, folder: folder);
  }

  Future<DriveFolderResult> _run({required bool createIfMissing}) async {
    if (_busy) {
      throw const DriveAccessFailure(DriveAccessIssue.operationInProgress);
    }
    _busy = true;
    try {
      final session = _session();
      final accountId = session.account.permissionId;
      final remembered = session.folder;
      final rootId = await _metadata.getMyDriveRootId(accountId: accountId);
      if (rootId.trim().isEmpty) {
        throw const DriveMetadataFailure(DriveMetadataIssue.incompleteResponse);
      }
      DriveFileMetadata? known;
      if (remembered != null) {
        _session(accountId);
        try {
          known = await _metadata.getFile(
            accountId: accountId,
            fileId: remembered.folderId,
          );
        } on DriveMetadataFailure catch (failure) {
          if (failure.issue == DriveMetadataIssue.notFound) {
            return DriveFolderResult._(DriveFolderStatus.missingOrInaccessible);
          }
          rethrow;
        }
        if (known.id != remembered.folderId) {
          throw const DriveMetadataFailure(
            DriveMetadataIssue.incompleteResponse,
          );
        }
        final invalid = _invalid(known, rootId);
        if (invalid != null) return DriveFolderResult._(invalid);
      }
      _session(accountId);
      // Buscar también fuera de root permite señalar una carpeta movida en una
      // instalación nueva, sin crear otra silenciosamente. No filtrar por nombre
      // ni MIME: una marca con tipo incorrecto también bloquea la creación.
      final discovered = await _metadata.listFiles(
        accountId: accountId,
        appProperties: driveAutofinanceFolderProperties,
      );
      _session(accountId);
      final candidates = <String, DriveFileMetadata>{};
      if (known != null) candidates[known.id] = known;
      for (final folder in discovered) {
        if (folder.id.trim().isEmpty ||
            folder.trashed ||
            !driveAutofinanceFolderProperties.entries.every(
              (entry) => folder.appProperties[entry.key] == entry.value,
            )) {
          throw const DriveMetadataFailure(
            DriveMetadataIssue.incompleteResponse,
          );
        }
        candidates[folder.id] = folder;
      }
      if (candidates.length > 1) {
        return DriveFolderResult._(
          DriveFolderStatus.ambiguous,
          candidateIds: candidates.keys.toList()..sort(),
        );
      }
      if (candidates.isNotEmpty) {
        final folder = candidates.values.single;
        final invalid = _invalid(folder, rootId);
        if (invalid != null) return DriveFolderResult._(invalid);
        return await _remember(accountId, folder, DriveFolderStatus.found);
      }
      if (_unconfirmedCreations.contains(accountId)) {
        return DriveFolderResult._(DriveFolderStatus.creationUnconfirmed);
      }
      if (!createIfMissing) {
        return DriveFolderResult._(DriveFolderStatus.notFound);
      }
      _session(accountId);
      _unconfirmedCreations.add(accountId);
      final DriveFileMetadata folder;
      try {
        folder = await _metadata.createAutofinanceFolder(accountId: accountId);
      } on DriveMetadataFailure catch (failure) {
        if (!{
          DriveMetadataIssue.networkFailure,
          DriveMetadataIssue.requestTimeout,
          DriveMetadataIssue.incompleteResponse,
          DriveMetadataIssue.serverUnavailable,
        }.contains(failure.issue)) {
          _unconfirmedCreations.remove(accountId);
        }
        rethrow;
      }
      if (folder.id.trim().isEmpty || _invalid(folder, rootId) != null) {
        throw const DriveMetadataFailure(DriveMetadataIssue.incompleteResponse);
      }
      // Comprobar de nuevo permite detectar carreras entre instalaciones. Drive
      // no ofrece unicidad por appProperties; nunca borrar ni escoger un duplicado.
      _session(accountId);
      final afterCreate = await _metadata.listFiles(
        accountId: accountId,
        appProperties: driveAutofinanceFolderProperties,
      );
      final ids = <String>{folder.id};
      for (final candidate in afterCreate) {
        if (candidate.id.trim().isEmpty ||
            candidate.trashed ||
            !driveAutofinanceFolderProperties.entries.every(
              (entry) => candidate.appProperties[entry.key] == entry.value,
            )) {
          throw const DriveMetadataFailure(
            DriveMetadataIssue.incompleteResponse,
          );
        }
        ids.add(candidate.id);
      }
      _session(accountId);
      if (ids.length > 1) {
        return DriveFolderResult._(
          DriveFolderStatus.ambiguous,
          candidateIds: ids.toList()..sort(),
        );
      }
      final latest = afterCreate.isEmpty ? folder : afterCreate.first;
      final invalid = _invalid(latest, rootId);
      if (invalid != null) return DriveFolderResult._(invalid);
      return await _remember(accountId, latest, DriveFolderStatus.created);
    } on DriveAccessFailure {
      rethrow;
    } on DriveMetadataFailure {
      rethrow;
    } catch (_) {
      // Un puerto externo no debe filtrar mensajes, IDs ni respuestas privadas.
      throw const DriveMetadataFailure(DriveMetadataIssue.incompleteResponse);
    } finally {
      _busy = false;
    }
  }
}
