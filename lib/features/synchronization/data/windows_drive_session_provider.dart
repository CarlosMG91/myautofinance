import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/drive_access.dart';
import 'windows_drive_session_store.dart';
import 'windows_google_authorization.dart';
import 'drive_metadata_credential.dart';

/// OAuth público y metadatos Drive; no lee archivos, SQLite ni copias.
final class WindowsDriveSessionProvider
    implements DriveSessionProvider, DriveMetadataCredentialSource {
  WindowsDriveSessionProvider({
    required this.clientId,
    required this._authorization,
    required this._store,
    required this._client,
    DateTime Function()? now,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _now = now ?? DateTime.now;

  final String clientId;
  final WindowsGoogleAuthorization _authorization;
  final WindowsDriveSessionStore _store;
  final http.Client _client;
  final DateTime Function() _now;
  final Duration requestTimeout;
  bool _busy = false;

  void cancelAuthorization() => _authorization.cancel();

  /// Solo Credential Manager; no abre navegador ni usa refresh_token.
  @override
  Future<DriveMetadataCredential> readCredential({required String accountId}) =>
      _exclusive(() async {
        final credential = await _read();
        if (credential == null ||
            !credential.session.validUntil.isAfter(_now()) ||
            credential.accessToken == null) {
          throw const DriveAccessFailure(DriveAccessIssue.credentialExpired);
        }
        if (credential.session.account.permissionId != accountId) {
          throw const DriveAccessFailure(
            DriveAccessIssue.accountChangeRequired,
          );
        }
        return DriveMetadataCredential(
          session: credential.session,
          accessToken: credential.accessToken!,
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

  Future<WindowsDriveCredential?> _read() async {
    if (!RegExp(r'^\d+-[a-z0-9]+\.apps\.googleusercontent\.com$')
        .hasMatch(clientId)) {
      throw const DriveAccessFailure(DriveAccessIssue.clientConfigurationError);
    }
    try {
      final credential = await _store.read();
      if (credential != null && credential.clientId != clientId) {
        throw const DriveAccessFailure(
          DriveAccessIssue.clientConfigurationError,
        );
      }
      return credential;
    } on DriveAccessFailure {
      rethrow;
    } catch (_) {
      throw const DriveAccessFailure(DriveAccessIssue.secureStorageFailure);
    }
  }

  Future<void> _write(WindowsDriveCredential credential) async {
    try {
      await _store.write(credential);
    } catch (_) {
      throw const DriveAccessFailure(DriveAccessIssue.secureStorageFailure);
    }
  }

  Future<void> _invalidate(WindowsDriveCredential previous) => _write(
    WindowsDriveCredential(
      clientId: clientId,
      session: DriveSession(
        account: previous.session.account,
        validUntil: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        grantedScopes: previous.session.grantedScopes,
        folder: previous.session.folder,
      ),
    ),
  );

  Future<http.Response> _send(http.Request request) async {
    request.followRedirects = false;
    return (() async => http.Response.fromStream(
      await _client.send(request),
    ))().timeout(requestTimeout);
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const DriveAccessFailure(DriveAccessIssue.invalidSession);
    }
  }

  Future<Map<String, dynamic>> _tokens(Map<String, String> fields) async {
    // PKCE sustituye cualquier confianza en un secreto incrustado.
    final response = await _send(
      http.Request('POST', Uri.https('oauth2.googleapis.com', '/token'))
        ..bodyFields = {'client_id': clientId, ...fields},
    );
    if (response.statusCode != 200) {
      final data = response.statusCode == 400 || response.statusCode == 401
          ? _decode(response)
          : const <String, dynamic>{};
      throw DriveAccessFailure(switch (data['error']) {
        'invalid_grant' => DriveAccessIssue.credentialExpired,
        'invalid_client' ||
        'unauthorized_client' ||
        'invalid_request' => DriveAccessIssue.clientConfigurationError,
        'access_denied' => DriveAccessIssue.permissionDenied,
        _ => DriveAccessIssue.unavailable,
      });
    }
    return _decode(response);
  }

  Future<DriveAccount> _account(String token) async {
    final response = await _send(
      http.Request(
        'GET',
        Uri.https('www.googleapis.com', '/drive/v3/about', {
          'fields': 'user(permissionId,emailAddress)',
        }),
      )..headers['Authorization'] = 'Bearer $token',
    );
    if (response.statusCode == 401) {
      throw const DriveAccessFailure(DriveAccessIssue.credentialExpired);
    }
    if (response.statusCode == 403) {
      throw const DriveAccessFailure(DriveAccessIssue.permissionDenied);
    }
    if (response.statusCode != 200) {
      throw const DriveAccessFailure(DriveAccessIssue.unavailable);
    }
    final user = _decode(response)['user'];
    if (user is! Map<String, dynamic> ||
        user['permissionId'] is! String ||
        (user['emailAddress'] != null && user['emailAddress'] is! String)) {
      throw const DriveAccessFailure(DriveAccessIssue.invalidSession);
    }
    return DriveAccount(
      permissionId: user['permissionId'] as String,
      emailAddress: user['emailAddress'] as String?,
    );
  }

  Future<DriveSession> _acceptTokens(
    Map<String, dynamic> data, {
    required WindowsDriveCredential? previous,
    required String? expectedAccountId,
    required DateTime requestedAt,
    required bool refreshing,
  }) async {
    final token = data['access_token'];
    final seconds = data['expires_in'];
    if (token is! String ||
        token.isEmpty ||
        data['token_type'] != 'Bearer' ||
        seconds is! int ||
        (data['scope'] != null && data['scope'] is! String) ||
        (data['refresh_token'] != null && data['refresh_token'] is! String)) {
      throw const DriveAccessFailure(DriveAccessIssue.invalidSession);
    }
    final scopes = data['scope'] == null && refreshing
        ? previous!.session.grantedScopes
        : (data['scope'] as String? ?? '')
              .split(' ')
              .where((s) => s.isNotEmpty)
              .toSet();
    if (scopes.length != 1 || !scopes.contains(driveFileScope)) {
      throw const DriveAccessFailure(DriveAccessIssue.permissionDenied);
    }
    final validUntil = requestedAt.add(Duration(seconds: seconds - 60));
    if (seconds <= 60 || !validUntil.isAfter(_now())) {
      throw const DriveAccessFailure(DriveAccessIssue.credentialExpired);
    }
    final account = await _account(token);
    if (expectedAccountId != null &&
        account.permissionId != expectedAccountId) {
      throw const DriveAccessFailure(DriveAccessIssue.accountChangeRequired);
    }
    if (!validUntil.isAfter(_now())) {
      throw const DriveAccessFailure(DriveAccessIssue.credentialExpired);
    }
    final sameAccount =
        previous?.session.account.permissionId == account.permissionId;
    final refresh =
        data['refresh_token'] as String? ??
        (sameAccount ? previous?.refreshToken : null);
    if (refresh == null || refresh.isEmpty) {
      throw const DriveAccessFailure(DriveAccessIssue.credentialExpired);
    }
    final session = DriveSession(
      account: account,
      validUntil: validUntil,
      grantedScopes: scopes,
      folder: sameAccount ? previous?.session.folder : null,
    );
    await _write(
      WindowsDriveCredential(
        clientId: clientId,
        session: session,
        accessToken: token,
        refreshToken: refresh,
      ),
    );
    return session;
  }

  Future<DriveSession> _refresh(WindowsDriveCredential previous) async {
    try {
      if (previous.refreshToken == null) {
        throw const DriveAccessFailure(DriveAccessIssue.credentialExpired);
      }
      final requestedAt = _now();
      final data = await _tokens({
        'grant_type': 'refresh_token',
        'refresh_token': previous.refreshToken!,
      });
      return await _acceptTokens(
        data,
        previous: previous,
        expectedAccountId: previous.session.account.permissionId,
        requestedAt: requestedAt,
        refreshing: true,
      );
    } on DriveAccessFailure catch (failure) {
      if ({
        DriveAccessIssue.credentialExpired,
        DriveAccessIssue.permissionDenied,
        DriveAccessIssue.accountChangeRequired,
      }.contains(failure.issue)) {
        await _invalidate(previous);
        throw const DriveAccessFailure(DriveAccessIssue.credentialExpired);
      }
      rethrow;
    }
  }

  @override
  Future<DriveSession?> readLocalSession() =>
      _exclusive(() async => (await _read())?.session);

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
    final expected =
        expectedAccountId ?? previous?.session.account.permissionId;
    if (previous != null && previous.session.account.permissionId != expected) {
      throw const DriveAccessFailure(DriveAccessIssue.accountChangeRequired);
    }
    if (!selectAccount && previous?.refreshToken != null) {
      if (previous!.accessToken != null &&
          previous.session.validUntil.isAfter(_now())) {
        try {
          final account = await _account(previous.accessToken!);
          if (account.permissionId != expected) {
            await _invalidate(previous);
            throw const DriveAccessFailure(
              DriveAccessIssue.accountChangeRequired,
            );
          }
          if (previous.session.validUntil.isAfter(_now())) {
            return previous.session;
          }
        } on DriveAccessFailure catch (failure) {
          if (failure.issue != DriveAccessIssue.credentialExpired) rethrow;
        }
      }
      return _refresh(previous);
    }
    final code = await _authorization.authorize(
      selectAccount: selectAccount,
      requireConsent: previous?.refreshToken == null,
      loginHint: previous?.session.account.emailAddress,
    );
    final requestedAt = _now();
    return _acceptTokens(
      await _tokens({
        'grant_type': 'authorization_code',
        'code': code.code,
        'code_verifier': code.verifier,
        'redirect_uri': code.redirectUri.toString(),
      }),
      previous: previous,
      expectedAccountId: expected,
      requestedAt: requestedAt,
      refreshing: false,
    );
  });

  @override
  Future<DriveSession> renew({required String accountId}) => _exclusive(
    () async {
      final previous = await _read();
      if (previous == null) {
        throw const DriveAccessFailure(DriveAccessIssue.credentialExpired);
      }
      if (previous.session.account.permissionId != accountId) {
        throw const DriveAccessFailure(DriveAccessIssue.accountChangeRequired);
      }
      return _refresh(previous);
    },
  );

  @override
  Future<void> clearLocalSession() => _exclusive(() async {
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
      if (previous == null || !previous.session.validUntil.isAfter(_now())) {
        throw const DriveAccessFailure(DriveAccessIssue.credentialExpired);
      }
      if (folder.accountId != previous.session.account.permissionId) {
        throw const DriveAccessFailure(DriveAccessIssue.accountChangeRequired);
      }
      await _write(
        WindowsDriveCredential(
          clientId: clientId,
          accessToken: previous.accessToken,
          refreshToken: previous.refreshToken,
          session: DriveSession(
            account: previous.session.account,
            validUntil: previous.session.validUntil,
            grantedScopes: previous.session.grantedScopes,
            folder: folder,
          ),
        ),
      );
    },
  );
}
