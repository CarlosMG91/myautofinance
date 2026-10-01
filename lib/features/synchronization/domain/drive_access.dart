/// Único permiso de Drive admitido; no incluye scopes de identidad.
const driveFileScope = 'https://www.googleapis.com/auth/drive.file';

enum DriveAccessStatus {
  disconnected,
  connecting,
  authorized,
  permissionDenied,
  credentialExpired,
  error,
}

/// Códigos cerrados: nunca contienen respuestas OAuth, URLs ni credenciales.
enum DriveAccessIssue {
  cancelled,
  permissionDenied,
  credentialExpired,
  unavailable,
  invalidSession,
  accountChangeRequired,
  operationInProgress,
  secureStorageFailure,
  clientConfigurationError,
}

final class DriveAccessFailure implements Exception {
  const DriveAccessFailure(this.issue);
  final DriveAccessIssue issue;

  @override
  String toString() => 'DriveAccessFailure(${issue.name})';
}

/// Identidad estable de Drive (User.permissionId), nunca el correo ni OIDC sub.
final class DriveAccount {
  DriveAccount({required this.permissionId, this.emailAddress}) {
    if (permissionId.trim().isEmpty) {
      throw const DriveAccessFailure(DriveAccessIssue.invalidSession);
    }
  }

  final String permissionId;

  /// Etiqueta opcional para el futuro flujo visible; no determina la identidad.
  final String? emailAddress;

  @override
  String toString() => 'DriveAccount';
}

/// Referencia local, siempre vinculada a la cuenta que concedió el acceso.
/// Recordarla no crea carpetas ni acredita acceso remoto por sí sola.
final class DriveFolderBinding {
  DriveFolderBinding({required this.accountId, required this.folderId}) {
    if (accountId.trim().isEmpty || folderId.trim().isEmpty) {
      throw const DriveAccessFailure(DriveAccessIssue.invalidSession);
    }
  }

  final String accountId;
  final String folderId;

  @override
  String toString() => 'DriveFolderBinding';
}

/// Metadatos de sesión. No representa ni transporta tokens o secretos.
final class DriveSession {
  DriveSession({
    required this.account,
    required this.validUntil,
    required Set<String> grantedScopes,
    this.folder,
  }) : grantedScopes = Set.unmodifiable(grantedScopes);

  final DriveAccount account;
  final DateTime validUntil;
  final Set<String> grantedScopes;
  final DriveFolderBinding? folder;

  @override
  String toString() => 'DriveSession';
}

final class DriveAccessSnapshot {
  const DriveAccessSnapshot({
    required this.status,
    this.account,
    this.session,
    this.issue,
  });

  final DriveAccessStatus status;
  final DriveAccount? account;

  /// Solo disponible mientras el acceso está autorizado y no ha caducado.
  final DriveSession? session;
  final DriveAccessIssue? issue;

  @override
  String toString() => 'DriveAccessSnapshot(${status.name}, ${issue?.name})';
}

/// Puerto de los adaptadores Windows/Android. Credenciales exclusivamente en
/// almacenamiento seguro local por instalación, excluido de backups/SQLite.
/// Ningún método registra secretos ni propaga errores crudos del SDK/OAuth.
abstract interface class DriveSessionProvider {
  /// Solo almacenamiento local. No consulta Drive ni renueva credenciales.
  Future<DriveSession?> readLocalSession();

  /// Único método interactivo. Solicita exactamente [scopes], verifica identidad
  /// y permisos antes de guardar atómicamente la sesión segura. Cancelar/fallar
  /// conserva la sesión anterior y su carpeta. expectedAccountId impide cambiar de cuenta;
  /// selectAccount fuerza elección expresa. Nunca crea recursos de Drive.
  Future<DriveSession> authorize({
    required Set<String> scopes,
    required String? expectedAccountId,
    required bool selectAccount,
  });

  /// Renovación sin UI, solo a petición del flujo manual de sincronización.
  /// Debe verificar la misma cuenta, conservar su carpeta y persistir de forma
  /// atómica. invalid_grant/revocación invalida también la credencial persistida
  /// (conservando identidad/carpeta y una validUntil caducada) y se traduce a
  /// credentialExpired. Nunca abre consentimiento para recuperarla por su cuenta.
  Future<DriveSession> renew({required String accountId});

  /// Borrado local idempotente de tokens, sesión y carpeta. No depende de red.
  /// Completa solo cuando se ha borrado; fallo => secureStorageFailure.
  /// No revoca permisos Google ni toca otras instalaciones o archivos remotos.
  Future<void> clearLocalSession();

  /// Solo escritura local segura y atómica. Rechaza una cuenta distinta de la
  /// sesión persistida; no busca ni crea carpetas. Conserva las credenciales.
  Future<void> rememberFolder(DriveFolderBinding folder);
}

/// Contrato común sin Flutter, SQLite ni dependencias de plataforma.
abstract interface class DriveAccess {
  /// Lectura pasiva; detecta caducidad local sin iniciar red ni temporizadores.
  DriveAccessSnapshot get snapshot;
  Stream<DriveAccessSnapshot> get changes;
  Future<DriveAccessSnapshot> restoreLocalSession();

  /// Acción expresa del usuario; mantiene la cuenta ya vinculada.
  Future<DriveAccessSnapshot> requestAccess();

  /// Acción expresa independiente: borra la sesión/carpeta previa antes de
  /// abrir la selección de cuenta. Cancelar deja la instalación desconectada.
  Future<DriveAccessSnapshot> changeAccount();
  Future<DriveAccessSnapshot> renewAccess();
  Future<DriveAccessSnapshot> disconnect();
  Future<DriveAccessSnapshot> rememberFolder(DriveFolderBinding folder);

  /// Libera observadores; no desconecta ni realiza operaciones remotas.
  Future<void> dispose();
}
