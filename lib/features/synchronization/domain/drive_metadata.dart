/// Metadatos exclusivamente; no representa contenido descargado de Drive.
const driveFolderMimeType = 'application/vnd.google-apps.folder';

enum DriveMetadataIssue {
  credentialExpired,
  permissionDenied,
  notFound,
  rateLimited,
  quotaExceeded,
  networkFailure,
  requestTimeout,
  incompleteResponse,
  serverUnavailable,
  invalidRequest,
  invalidCredential,
  accountChangeRequired,
  credentialUnavailable,
}

/// Códigos cerrados, sin mensajes remotos, URLs, IDs ni credenciales.
final class DriveMetadataFailure implements Exception {
  const DriveMetadataFailure(this.issue, {this.httpStatus, this.retryAfter});
  final DriveMetadataIssue issue;
  final int? httpStatus;

  /// Orientación para un futuro reintento del flujo manual, nunca un temporizador.
  final Duration? retryAfter;

  @override
  String toString() => 'DriveMetadataFailure(${issue.name}, $httpStatus)';
}

final class DriveFileMetadata {
  DriveFileMetadata({
    required this.id,
    required this.name,
    required this.mimeType,
    required List<String> parents,
    required this.trashed,
    this.modifiedTime,
    this.size,
    this.md5Checksum,
    this.version,
  }) : parents = List.unmodifiable(parents);

  final String id;
  final String name;
  final String mimeType;
  final List<String> parents;
  final bool trashed;

  /// Campos opcionales de Drive: una carpeta no tiene tamaño ni checksum.
  final DateTime? modifiedTime;
  final int? size;
  final String? md5Checksum;
  final String? version;

  @override
  String toString() => 'DriveFileMetadata';
}

/// Puerto simulable para el futuro localizador de carpeta/copia.
/// Todas las llamadas pertenecen a una acción manual con una cuenta concreta.
/// No autoriza, renueva sesión, crea archivos vacíos ni transfiere medios.
abstract interface class DriveMetadataClient {
  /// Filtra trashed=false; devuelve todas las páginas o falla sin resultado
  /// parcial. Sin coincidencias devuelve una lista vacía y no crea recursos.
  Future<List<DriveFileMetadata>> listFiles({
    required String accountId,
    String? parentId,
    String? name,
    String? mimeType,
  });

  /// files.get solo admite metadatos; un elemento en papelera es notFound.
  Future<DriveFileMetadata> getFile({
    required String accountId,
    required String fileId,
  });

  /// Única escritura: carpeta normal Autofinance en Mi unidad. El consumidor
  /// solo la invoca tras una acción expresa; no se llama al buscar ni autorizar.
  Future<DriveFileMetadata> createAutofinanceFolder({
    required String accountId,
  });
}
