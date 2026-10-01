import '../domain/drive_access.dart';

/// Credencial efímera en la capa data, nunca en DriveSession ni en SQLite.
/// La fuente de plataforma debe acreditar que el token pertenece a esta sesión
/// y a su permiso exacto. No se registra ni se persiste desde el cliente HTTP.
final class DriveMetadataCredential {
  const DriveMetadataCredential({
    required this.session,
    required this.accessToken,
  });
  final DriveSession session;
  final String accessToken;

  @override
  String toString() => 'DriveMetadataCredential';
}

/// Adaptación de credenciales por constructor, sin dependencia del SDK OAuth.
/// Solo se consulta al invocar una operación manual; no debe abrir consentimiento
/// ni renovar acceso. Una credencial caducada requiere el flujo DriveAccess.
abstract interface class DriveMetadataCredentialSource {
  Future<DriveMetadataCredential> readCredential({required String accountId});
}
