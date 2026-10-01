import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/drive_access.dart';

/// Un registro cifrado y atómico, excluido del backup Android.
abstract interface class AndroidDriveSessionStore {
  Future<DriveSession?> read();
  Future<void> write(DriveSession session);
  Future<void> clear();
}

final class KeystoreDriveSessionStore implements AndroidDriveSessionStore {
  const KeystoreDriveSessionStore({
    this._channel = const MethodChannel('autofinance/drive_session'),
  });
  final MethodChannel _channel;

  @override
  Future<DriveSession?> read() async {
    try {
      final raw = await _channel.invokeMethod<String>('read');
      if (raw == null) return null;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['version'] != 1) throw const FormatException();
      final folder = data['folderId'] as String?;
      final session = DriveSession(
        account: DriveAccount(
          permissionId: data['accountId'] as String,
          emailAddress: data['emailAddress'] as String?,
        ),
        validUntil: DateTime.parse(data['validUntil'] as String),
        grantedScopes: (data['scopes'] as List).cast<String>().toSet(),
        folder: folder == null
            ? null
            : DriveFolderBinding(
                accountId: data['accountId'] as String,
                folderId: folder,
              ),
      );
      if (session.grantedScopes.length != 1 ||
          !session.grantedScopes.contains(driveFileScope)) {
        throw const FormatException();
      }
      return session;
    } catch (_) {
      throw const DriveAccessFailure(DriveAccessIssue.secureStorageFailure);
    }
  }

  @override
  Future<void> write(DriveSession session) async {
    try {
      await _channel.invokeMethod<void>(
        'write',
        jsonEncode({
          'version': 1,
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
      await _channel.invokeMethod<void>('clear');
    } catch (_) {
      throw const DriveAccessFailure(DriveAccessIssue.secureStorageFailure);
    }
  }
}
