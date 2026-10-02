import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/drive_access.dart';
import 'android_drive_session_store.dart';
import 'android_google_authorization.dart';
import 'drive_metadata_credential.dart';

/// Solo identidad y validación OAuth: no opera sobre archivos ni SQLite.
final class AndroidDriveSessionProvider
    implements DriveSessionProvider, DriveMetadataCredentialSource {
  AndroidDriveSessionProvider({
    required this._authorization,
    required this._store,
    required this._client,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AndroidGoogleAuthorization _authorization;
  final AndroidDriveSessionStore _store;
  final http.Client _client;
  final DateTime Function() _now;
  bool _busy = false;
  DriveMetadataCredential? _credential;

  /// Lectura local de un token ya verificado; nunca llama al SDK ni renueva.
  /// Tras reiniciar, requestAccess/renewAccess debe obtenerlo expresamente.
  @override
  Future<DriveMetadataCredential> readCredential({required String accountId}) =>
      _exclusive(() async {
        final session = await _read();
        final credential = _credential;
        if (session == null || !session.validUntil.isAfter(_now())) {
          throw const DriveAccessFailure(DriveAccessIssue.credentialExpired);
        }
        if (session.account.permissionId != accountId) {
          throw const DriveAccessFailure(
            DriveAccessIssue.accountChangeRequired,
          );
        }
        if (credential == null ||
            credential.session.account.permissionId != accountId ||
            credential.session.validUntil != session.validUntil) {
          throw const DriveAccessFailure(DriveAccessIssue.unavailable);
        }
        return DriveMetadataCredential(
          session: session,
          accessToken: credential.accessToken,
        );
      });

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    if (_busy) {
      throw const DriveAccessFailure(DriveAccessIssue.operationInProgress);
    }
    _busy = true;
    try {
      return await action();
    } on DriveAccessFailure {
      rethrow;
    } catch (_) {
      throw const DriveAccessFailure(DriveAccessIssue.unavailable);
    } finally {
      _busy = false;
    }
  }

  Future<DriveSession?> _read() async {
    try {
      return await _store.read();
    } catch (_) {
      throw const DriveAccessFailure(DriveAccessIssue.secureStorageFailure);
    }
  }

  Future<void> _write(DriveSession session) async {
    try {
      await _store.write(session);
    } catch (_) {
      throw const DriveAccessFailure(DriveAccessIssue.secureStorageFailure);
    }
  }

  @override
  Future<DriveSession?> readLocalSession() => _exclusive(_read);

  Future<Map<String, dynamic>> _get(Uri uri, String token) async {
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers['Authorization'] = 'Bearer $token';
    final response = await (() async => http.Response.fromStream(
      await _client.send(request),
    ))().timeout(const Duration(seconds: 30));
    if (response.statusCode == 401) {
      throw const DriveAccessFailure(DriveAccessIssue.credentialExpired);
    }
    if (response.statusCode == 403) {
      throw const DriveAccessFailure(DriveAccessIssue.permissionDenied);
    }
    if (response.statusCode != 200) {
      throw DriveAccessFailure(
        uri.host == 'oauth2.googleapis.com' && response.statusCode == 400
            ? DriveAccessIssue.credentialExpired
            : DriveAccessIssue.unavailable,
      );
    }
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const DriveAccessFailure(DriveAccessIssue.invalidSession);
    }
  }

  Future<DriveSession> _validate({
    required bool interactive,
    required bool selectAccount,
    required String? expectedAccountId,
    required DriveSession? previous,
  }) async {
    _credential = null;
    final token = await _authorization.accessToken(
      interactive: interactive,
      selectAccount: selectAccount,
    );
    // El SDK no devuelve scopes ni caducidad: verificarlos antes de persistir.
    final checkedAt = _now();
    final info = await _get(
      Uri.https('oauth2.googleapis.com', '/tokeninfo', {'access_token': token}),
      token,
    );
    if (info['scope'] != null && info['scope'] is! String) {
      throw const DriveAccessFailure(DriveAccessIssue.invalidSession);
    }
    final scopes = (info['scope'] as String? ?? '')
        .split(' ')
        .where((s) => s.isNotEmpty)
        .toSet();
    if (scopes.length != 1 || !scopes.contains(driveFileScope)) {
      throw const DriveAccessFailure(DriveAccessIssue.permissionDenied);
    }
    final seconds = int.tryParse('${info['expires_in']}');
    if (seconds == null || seconds <= 60) {
      throw const DriveAccessFailure(DriveAccessIssue.credentialExpired);
    }
    final about = await _get(
      Uri.https('www.googleapis.com', '/drive/v3/about', {
        'fields': 'user(permissionId,emailAddress)',
      }),
      token,
    );
    final user = about['user'];
    if (user is! Map<String, dynamic> || user['permissionId'] is! String) {
      throw const DriveAccessFailure(DriveAccessIssue.invalidSession);
    }
    final account = DriveAccount(
      permissionId: user['permissionId'] as String,
      emailAddress: user['emailAddress'] as String?,
    );
    if (expectedAccountId != null &&
        account.permissionId != expectedAccountId) {
      throw const DriveAccessFailure(DriveAccessIssue.accountChangeRequired);
    }
    final validUntil = checkedAt.add(Duration(seconds: seconds - 60));
    if (!validUntil.isAfter(_now())) {
      throw const DriveAccessFailure(DriveAccessIssue.credentialExpired);
    }
    final session = DriveSession(
      account: account,
      validUntil: validUntil,
      grantedScopes: scopes,
      folder: previous?.account.permissionId == account.permissionId
          ? previous?.folder
          : null,
    );
    await _write(session);
    _credential = DriveMetadataCredential(session: session, accessToken: token);
    return session;
  }

  @override
  Future<DriveSession> authorize({
    required Set<String> scopes,
    required String? expectedAccountId,
    required bool selectAccount,
  }) => _exclusive(() async {
    if (scopes.length != 1 || !scopes.contains(driveFileScope)) {
      throw const DriveAccessFailure(DriveAccessIssue.invalidSession);
    }
    final previous = await _read();
    if (previous != null &&
        expectedAccountId != null &&
        previous.account.permissionId != expectedAccountId) {
      throw const DriveAccessFailure(DriveAccessIssue.accountChangeRequired);
    }
    return _validate(
      interactive: true,
      selectAccount: selectAccount,
      expectedAccountId: expectedAccountId ?? previous?.account.permissionId,
      previous: previous,
    );
  });

  @override
  Future<DriveSession> renew({required String accountId}) => _exclusive(
    () async {
      final previous = await _read();
      if (previous == null) {
        throw const DriveAccessFailure(DriveAccessIssue.credentialExpired);
      }
      if (previous.account.permissionId != accountId) {
        throw const DriveAccessFailure(DriveAccessIssue.accountChangeRequired);
      }
      try {
        return await _validate(
          interactive: false,
          selectAccount: false,
          expectedAccountId: accountId,
          previous: previous,
        );
      } on DriveAccessFailure catch (error) {
        if ({
          DriveAccessIssue.cancelled,
          DriveAccessIssue.permissionDenied,
          DriveAccessIssue.credentialExpired,
          DriveAccessIssue.accountChangeRequired,
        }.contains(error.issue)) {
          _authorization.forget();
          await _write(
            DriveSession(
              account: previous.account,
              validUntil: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
              grantedScopes: previous.grantedScopes,
              folder: previous.folder,
            ),
          );
          throw const DriveAccessFailure(DriveAccessIssue.credentialExpired);
        }
        rethrow;
      }
    },
  );

  @override
  Future<void> clearLocalSession() => _exclusive(() async {
    _credential = null;
    _authorization.forget();
    try {
      await _store.clear();
    } catch (_) {
      throw const DriveAccessFailure(DriveAccessIssue.secureStorageFailure);
    }
  });

  @override
  Future<void> rememberFolder(DriveFolderBinding folder) => _exclusive(
    () async {
      final previous = await _read();
      if (previous == null || !previous.validUntil.isAfter(_now())) {
        throw const DriveAccessFailure(DriveAccessIssue.credentialExpired);
      }
      if (folder.accountId != previous.account.permissionId) {
        throw const DriveAccessFailure(DriveAccessIssue.accountChangeRequired);
      }
      await _write(
        DriveSession(
          account: previous.account,
          validUntil: previous.validUntil,
          grantedScopes: previous.grantedScopes,
          folder: folder,
        ),
      );
    },
  );
}
