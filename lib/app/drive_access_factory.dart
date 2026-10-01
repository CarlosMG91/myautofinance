import 'dart:io';

import 'package:http/http.dart' as http;

import '../features/synchronization/data/android_drive_session_provider.dart';
import '../features/synchronization/data/android_drive_session_store.dart';
import '../features/synchronization/data/android_google_authorization.dart';
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
  if (!Platform.isAndroid) {
    throw const DriveAccessFailure(DriveAccessIssue.unavailable);
  }
  return DriveAccessSession(
    provider: AndroidDriveSessionProvider(
      authorization: GoogleSignInAuthorization(serverClientId: serverClientId),
      store: const KeystoreDriveSessionStore(),
      client: client,
    ),
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
  if (!Platform.isWindows) {
    throw const DriveAccessFailure(DriveAccessIssue.unavailable);
  }
  final provider = WindowsDriveSessionProvider(
    clientId: clientId,
    authorization: LoopbackGoogleAuthorization(clientId: clientId),
    store: const CredentialManagerDriveSessionStore(),
    client: client,
  );
  return WindowsDriveAccessHandle(
    DriveAccessSession(provider: provider),
    provider.cancelAuthorization,
  );
}
