import 'drive_access.dart';
import 'drive_metadata.dart';

enum DriveCopyStatus { present, noCopy, ambiguous, inaccessible }

enum DriveCopyIssue {
  folderNotSelected,
  invalidFolder,
  invalidCopy,
  copyOutsideFolder,
}

/// Referencia opcional que el futuro flujo conservará fuera de la copia SQLite.
/// Solo puede reutilizarse con la misma cuenta y carpeta; no acredita acceso.
final class DriveCopyBinding {
  DriveCopyBinding({
    required this.accountId,
    required this.folderId,
    required this.fileId,
  }) {
    if ([accountId, folderId, fileId].any((id) => id.trim().isEmpty)) {
      throw const DriveAccessFailure(DriveAccessIssue.invalidSession);
    }
  }

  final String accountId;
  final String folderId;
  final String fileId;

  @override
  String toString() => 'DriveCopyBinding';
}

/// Solo present contiene copy, con ID, nombre actual, versión y fecha completos.
/// No acredita integridad SQLite ni que una descarga/reemplazo sea segura.
final class DriveCopyResult {
  DriveCopyResult._(
    this.status, {
    required this.account,
    required this.folder,
    this.copy,
    List<DriveFileMetadata> candidates = const [],
    this.issue,
    this.metadataFailure,
    this.accessIssue,
  }) : candidates = List.unmodifiable(candidates);

  final DriveCopyStatus status;

  /// Puede faltar solo si la instalación no tiene una identidad local conocida.
  final DriveAccount? account;
  final DriveFolderBinding? folder;
  final DriveFileMetadata? copy;
  final List<DriveFileMetadata> candidates;
  final DriveCopyIssue? issue;
  final DriveMetadataFailure? metadataFailure;
  final DriveAccessIssue? accessIssue;

  @override
  String toString() => 'DriveCopyResult(${status.name})';
}

/// Consulta manual común a Windows/Android, sin persistencia ni efectos remotos.
/// Antes de llamar, el flujo resuelve la carpeta mediante DriveFolderLocator.
final class DriveCopyLocator {
  DriveCopyLocator({required this._access, required this._metadata});

  final DriveAccess _access;
  final DriveMetadataClient _metadata;
  bool _busy = false;

  DriveSession _session(DriveFolderBinding folder) {
    final session = _access.snapshot.session;
    if (session == null) {
      throw const DriveAccessFailure(DriveAccessIssue.credentialExpired);
    }
    if (session.account.permissionId != folder.accountId ||
        session.folder?.accountId != folder.accountId ||
        session.folder?.folderId != folder.folderId) {
      throw const DriveAccessFailure(DriveAccessIssue.accountChangeRequired);
    }
    if (session.grantedScopes.length != 1 ||
        !session.grantedScopes.contains(driveFileScope)) {
      throw const DriveAccessFailure(DriveAccessIssue.permissionDenied);
    }
    return session;
  }

  bool _marked(DriveFileMetadata file, Map<String, String> properties) =>
      properties.entries.every((e) => file.appProperties[e.key] == e.value);

  DriveCopyIssue? _invalidCopy(
    DriveFileMetadata file,
    DriveFolderBinding folder,
  ) {
    if (file.parents.length != 1 || file.parents.single != folder.folderId) {
      return DriveCopyIssue.copyOutsideFolder;
    }
    if (!_marked(file, driveAutofinanceCopyProperties) ||
        file.mimeType.trim().isEmpty ||
        file.mimeType.startsWith('application/vnd.google-apps.')) {
      return DriveCopyIssue.invalidCopy;
    }
    return null;
  }

  /// Sin copia => esperar a la primera subida válida. Nunca crear archivo vacío.
  /// Un ID conocido no tiene preferencia sobre otras candidatas marcadas.
  Future<DriveCopyResult> findCopy({DriveCopyBinding? knownCopy}) async {
    if (_busy) {
      throw const DriveAccessFailure(DriveAccessIssue.operationInProgress);
    }
    _busy = true;
    final initial = _access.snapshot;
    final account = initial.session?.account ?? initial.account;
    final folder = initial.session?.folder;
    DriveCopyResult inaccessible({
      DriveCopyIssue? issue,
      DriveMetadataFailure? metadataFailure,
      DriveAccessIssue? accessIssue,
    }) => DriveCopyResult._(
      DriveCopyStatus.inaccessible,
      account: account,
      folder: folder,
      issue: issue,
      metadataFailure: metadataFailure,
      accessIssue: accessIssue,
    );
    try {
      if (initial.session == null) {
        return inaccessible(
          accessIssue: initial.issue ?? DriveAccessIssue.credentialExpired,
        );
      }
      if (folder == null) {
        return inaccessible(issue: DriveCopyIssue.folderNotSelected);
      }
      _session(folder);
      if (knownCopy != null &&
          (knownCopy.accountId != folder.accountId ||
              knownCopy.folderId != folder.folderId)) {
        return inaccessible(
          accessIssue: DriveAccessIssue.accountChangeRequired,
        );
      }
      final rootId = await _metadata.getMyDriveRootId(
        accountId: folder.accountId,
      );
      _session(folder);
      final remoteFolder = await _metadata.getFile(
        accountId: folder.accountId,
        fileId: folder.folderId,
      );
      _session(folder);
      if (rootId.trim().isEmpty || remoteFolder.id != folder.folderId) {
        throw const DriveMetadataFailure(DriveMetadataIssue.incompleteResponse);
      }
      if (remoteFolder.trashed ||
          remoteFolder.mimeType != driveFolderMimeType ||
          !_marked(remoteFolder, driveAutofinanceFolderProperties) ||
          remoteFolder.parents.length != 1 ||
          remoteFolder.parents.single != rootId) {
        return inaccessible(issue: DriveCopyIssue.invalidFolder);
      }
      final candidates = <String, DriveFileMetadata>{};
      if (knownCopy != null) {
        final known = await _metadata.getFile(
          accountId: folder.accountId,
          fileId: knownCopy.fileId,
        );
        _session(folder);
        if (known.id != knownCopy.fileId) {
          throw const DriveMetadataFailure(
            DriveMetadataIssue.incompleteResponse,
          );
        }
        if (known.trashed) {
          throw const DriveMetadataFailure(DriveMetadataIssue.notFound);
        }
        final invalid = _invalidCopy(known, folder);
        if (invalid != null) return inaccessible(issue: invalid);
        candidates[known.id] = known;
      }
      final discovered = await _metadata.listFiles(
        accountId: folder.accountId,
        parentId: folder.folderId,
        appProperties: driveAutofinanceCopyProperties,
      );
      _session(folder);
      for (final file in discovered) {
        if (file.trashed) continue;
        if (file.id.trim().isEmpty) {
          throw const DriveMetadataFailure(
            DriveMetadataIssue.incompleteResponse,
          );
        }
        final invalid = _invalidCopy(file, folder);
        if (invalid != null) return inaccessible(issue: invalid);
        candidates[file.id] = file;
      }
      if (candidates.isEmpty) {
        return DriveCopyResult._(
          DriveCopyStatus.noCopy,
          account: account,
          folder: folder,
        );
      }
      if (candidates.length > 1) {
        return DriveCopyResult._(
          DriveCopyStatus.ambiguous,
          account: account,
          folder: folder,
          candidates: candidates.values.toList()
            ..sort((a, b) => a.id.compareTo(b.id)),
        );
      }
      final copy = candidates.values.single;
      if (copy.name.trim().isEmpty ||
          copy.version == null ||
          !RegExp(r'^\d+$').hasMatch(copy.version!) ||
          copy.modifiedTime == null) {
        throw const DriveMetadataFailure(DriveMetadataIssue.incompleteResponse);
      }
      return DriveCopyResult._(
        DriveCopyStatus.present,
        account: account,
        folder: folder,
        copy: copy,
      );
    } on DriveAccessFailure catch (failure) {
      return inaccessible(accessIssue: failure.issue);
    } on DriveMetadataFailure catch (failure) {
      return inaccessible(metadataFailure: failure);
    } catch (_) {
      return inaccessible(
        metadataFailure: const DriveMetadataFailure(
          DriveMetadataIssue.incompleteResponse,
        ),
      );
    } finally {
      _busy = false;
    }
  }
}
