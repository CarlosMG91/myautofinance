import 'package:google_sign_in/google_sign_in.dart';

import '../domain/drive_access.dart';

/// El token queda dentro de datos; nunca se exporta desde synchronization.
abstract interface class AndroidGoogleAuthorization {
  Future<String> accessToken({
    required bool interactive,
    required bool selectAccount,
  });
  void forget();
}

final class GoogleSignInAuthorization implements AndroidGoogleAuthorization {
  GoogleSignInAuthorization({required this._serverClientId});

  final String _serverClientId;
  final _google = GoogleSignIn.instance;
  static Future<void>? _initialization;
  static String? _initializedClientId;
  GoogleSignInAccount? _account;
  String? _token;

  Future<void> _initialize() async {
    if (!RegExp(r'^\d+-[a-z0-9]+\.apps\.googleusercontent\.com$')
        .hasMatch(_serverClientId)) {
      throw const DriveAccessFailure(DriveAccessIssue.clientConfigurationError);
    }
    if (_initializedClientId != null &&
        _initializedClientId != _serverClientId) {
      throw const DriveAccessFailure(DriveAccessIssue.clientConfigurationError);
    }
    _initializedClientId = _serverClientId;
    await (_initialization ??= _google.initialize(
      serverClientId: _serverClientId,
    ));
  }

  @override
  Future<String> accessToken({
    required bool interactive,
    required bool selectAccount,
  }) async {
    try {
      await _initialize();
      if (selectAccount) {
        await _google
            .signOut(); // Local: no revoca permisos ni borra la cuenta Google.
        forget();
      }
      if (!interactive && _token != null) {
        await _google.authorizationClient.clearAuthorizationToken(
          accessToken: _token!,
        );
        _token = null;
      }
      // LightweightAuthentication de Android puede mostrar un selector.
      // Renovar nunca llama a ningún método de autenticación con UI posible.
      if (interactive && (selectAccount || _account == null)) {
        _account = await _google.authenticate();
      }
      final authorizationClient =
          _account?.authorizationClient ?? _google.authorizationClient;
      const scopes = [driveFileScope];
      var authorization = await authorizationClient.authorizationForScopes(
        scopes,
      );
      if (authorization == null && interactive) {
        authorization = await authorizationClient.authorizeScopes(scopes);
      }
      if (authorization == null || authorization.accessToken.isEmpty) {
        throw const DriveAccessFailure(DriveAccessIssue.credentialExpired);
      }
      return _token = authorization.accessToken;
    } on GoogleSignInException catch (error) {
      throw DriveAccessFailure(switch (error.code) {
        GoogleSignInExceptionCode.canceled => DriveAccessIssue.cancelled,
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError =>
          DriveAccessIssue.clientConfigurationError,
        GoogleSignInExceptionCode.userMismatch =>
          DriveAccessIssue.accountChangeRequired,
        _ => DriveAccessIssue.unavailable,
      });
    } on DriveAccessFailure {
      rethrow;
    } catch (_) {
      throw const DriveAccessFailure(DriveAccessIssue.unavailable);
    }
  }

  @override
  void forget() {
    _account = null;
    _token = null;
  }
}
