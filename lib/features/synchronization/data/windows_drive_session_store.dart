import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/drive_access.dart';

/// Registro único interno. Los tokens nunca forman parte de DriveSession.
final class WindowsDriveCredential {
  const WindowsDriveCredential({
    required this.clientId,
    required this.session,
    this.accessToken,
    this.refreshToken,
  });
  final String clientId;
  final DriveSession session;
  final String? accessToken;
  final String? refreshToken;
  @override
  String toString() => 'WindowsDriveCredential';
}

abstract interface class WindowsDriveSessionStore {
  Future<WindowsDriveCredential?> read();
  Future<void> write(WindowsDriveCredential credential);
  Future<void> clear();
}

/// Credential Manager con persistencia local a la máquina, por instalación.
final class CredentialManagerDriveSessionStore
    implements WindowsDriveSessionStore {
  const CredentialManagerDriveSessionStore({
    this.channel = const MethodChannel('autofinance/windows_drive'),
  });
  final MethodChannel channel;

  @override
  Future<WindowsDriveCredential?> read() async {
    try {
      final raw = await channel.invokeMethod<String>('read');
      if (raw == null) return null;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['version'] != 1) throw const FormatException();
      final account = DriveAccount(
        permissionId: data['accountId'] as String,
        emailAddress: data['emailAddress'] as String?,
      );
      final scopes = (data['scopes'] as List).cast<String>().toSet();
      if (scopes.length != 1 || !scopes.contains(driveFileScope)) {
        throw const FormatException();
      }
      final folder = data['folderId'] as String?;
      final credential = WindowsDriveCredential(
        clientId: data['clientId'] as String,
        accessToken: data['accessToken'] as String?,
        refreshToken: data['refreshToken'] as String?,
        session: DriveSession(
          account: account,
          validUntil: DateTime.parse(data['validUntil'] as String),
          grantedScopes: scopes,
          folder: folder == null
              ? null
              : DriveFolderBinding(
                  accountId: account.permissionId,
                  folderId: folder,
                ),
        ),
      );
      if (credential.clientId.isEmpty ||
          credential.accessToken == '' ||
          credential.refreshToken == '') {
        throw const FormatException();
      }
      return credential;
    } catch (_) {
      throw const DriveAccessFailure(DriveAccessIssue.secureStorageFailure);
    }
  }

  @override
  Future<void> write(WindowsDriveCredential credential) async {
    try {
      final session = credential.session;
      if (session.grantedScopes.length != 1 ||
          !session.grantedScopes.contains(driveFileScope) ||
          (session.folder != null &&
              session.folder!.accountId != session.account.permissionId)) {
        throw const FormatException();
      }
      await channel.invokeMethod<void>(
        'write',
        jsonEncode({
          'version': 1,
          'clientId': credential.clientId,
          'accessToken': credential.accessToken,
          'refreshToken': credential.refreshToken,
          'accountId': session.account.permissionId,
          'emailAddress': session.account.emailAddress,
          'validUntil': session.validUntil.toUtc().toIso8601String(),
          'scopes': session.grantedScopes.toList(),
          'folderId': session.folder?.folderId,
        }),
      );
    } catch (_) {
      throw const DriveAccessFailure(DriveAccessIssue.secureStorageFailure);
    }
  }

  @override
  Future<void> clear() async {
    try {
      await channel.invokeMethod<void>('clear');
    } catch (_) {
      throw const DriveAccessFailure(DriveAccessIssue.secureStorageFailure);
    }
  }
}
