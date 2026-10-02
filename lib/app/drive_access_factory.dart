import 'dart:io';

import 'package:http/http.dart' as http;

import '../features/synchronization/data/android_drive_session_provider.dart';
import '../features/synchronization/data/android_drive_session_store.dart';
import '../features/synchronization/data/android_google_authorization.dart';
import '../features/synchronization/data/drive_metadata_credential.dart';
import '../features/synchronization/data/http_drive_metadata_client.dart';
import '../features/synchronization/data/http_drive_transfer_client.dart';
import '../features/synchronization/data/windows_drive_session_provider.dart';
import '../features/synchronization/data/windows_drive_session_store.dart';
import '../features/synchronization/data/windows_google_authorization.dart';
import '../features/synchronization/synchronization.dart';

/// Composición optativa; el arranque no autoriza ni restaura sesión.
/// El llamante es propietario del cliente HTTP y debe cerrarlo al terminar.
DriveAccess createAndroidDriveAccess({
  required String serverClientId,
  required http.Client client,
}) {
  return DriveAccessSession(
    provider: _androidProvider(serverClientId: serverClientId, client: client),
  );
}

AndroidDriveSessionProvider _androidProvider({
  required String serverClientId,
  required http.Client client,
}) {
  if (!Platform.isAndroid) {
    throw const DriveAccessFailure(DriveAccessIssue.unavailable);
  }
  return AndroidDriveSessionProvider(
    authorization: GoogleSignInAuthorization(serverClientId: serverClientId),
    store: const KeystoreDriveSessionStore(),
    client: client,
  );
}

/// El consumidor puede cancelar el consentimiento en curso sin añadir UI aquí.
final class WindowsDriveAccessHandle {
  const WindowsDriveAccessHandle(this.access, this.cancelAuthorization);
  final DriveAccess access;
  final void Function() cancelAuthorization;
}

WindowsDriveAccessHandle createWindowsDriveAccess({
  required String clientId,
  required http.Client client,
}) {
  final provider = _windowsProvider(clientId: clientId, client: client);
  return WindowsDriveAccessHandle(
    DriveAccessSession(provider: provider),
    provider.cancelAuthorization,
  );
}

WindowsDriveSessionProvider _windowsProvider({
  required String clientId,
  required http.Client client,
}) {
  if (!Platform.isWindows) {
    throw const DriveAccessFailure(DriveAccessIssue.unavailable);
  }
  return WindowsDriveSessionProvider(
    clientId: clientId,
    authorization: LoopbackGoogleAuthorization(clientId: clientId),
    store: const CredentialManagerDriveSessionStore(),
    client: client,
  );
}

/// Una instancia por instalación/flujo manual. Construir no realiza acciones.
/// El llamante conserva y cierra client tras dispose y terminar transferencias.
final class DriveAccessInstallation {
  DriveAccessInstallation._({
    required this.access,
    required this.metadata,
    required this.transfers,
    required this.cancelAuthorization,
  }) : folders = DriveFolderLocator(access: access, metadata: metadata),
       copies = DriveCopyLocator(access: access, metadata: metadata);

  /// Punto de composición simulable; provider y credentials deben representar
  /// la misma sesión. Las fábricas nativas usan una única instancia para ambos.
  factory DriveAccessInstallation({
    required DriveSessionProvider provider,
    required DriveMetadataCredentialSource credentials,
    required http.Client client,
    DateTime Function()? now,
    void Function()? cancelAuthorization,
  }) => DriveAccessInstallation._(
    access: DriveAccessSession(provider: provider, now: now),
    metadata: HttpDriveMetadataClient(
      client: client,
      credentials: credentials,
      now: now,
    ),
    cancelAuthorization: cancelAuthorization,
    transfers: HttpDriveTransferClient(
      client: client,
      credentials: credentials,
      now: now,
    ),
  );

  final DriveAccess access;
  final DriveMetadataClient metadata;
  final DriveTransferClient transfers;
  final DriveFolderLocator folders;
  final DriveCopyLocator copies;
  final void Function()? cancelAuthorization;

  Future<void> dispose() => access.dispose();
}

DriveAccessInstallation createAndroidDriveInstallation({
  required String serverClientId,
  required http.Client client,
}) {
  final provider = _androidProvider(
    serverClientId: serverClientId,
    client: client,
  );
  return DriveAccessInstallation(
    provider: provider,
    credentials: provider,
    client: client,
  );
}

DriveAccessInstallation createWindowsDriveInstallation({
  required String clientId,
  required http.Client client,
}) {
  final provider = _windowsProvider(clientId: clientId, client: client);
  return DriveAccessInstallation(
    provider: provider,
    credentials: provider,
    client: client,
    cancelAuthorization: provider.cancelAuthorization,
  );
}
