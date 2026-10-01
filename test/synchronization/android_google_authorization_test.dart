import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:myautofinance/features/synchronization/data/android_google_authorization.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';

final class NativeGoogle extends GoogleSignInPlatform {
  final calls = <String>[];
  final requests = <AuthorizationRequestDetails>[];
  GoogleSignInExceptionCode? failure;
  bool granted = true;
  @override
  Future<void> init(InitParameters params) async {
    calls.add('init');
    expect(params.clientId, isNull);
    expect(
      params.serverClientId,
      '123456789012-synthetic.apps.googleusercontent.com',
    );
  }

  @override
  bool supportsAuthenticate() => true;
  @override
  bool authorizationRequiresUserInteraction() => false;
  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
    ServerAuthorizationTokensForScopesParameters params,
  ) async {
    fail('No debe solicitar acceso offline ni códigos de servidor');
  }

  @override
  Future<AuthenticationResults> authenticate(
    AuthenticateParameters params,
  ) async {
    calls.add('authenticate');
    expect(params.scopeHint, isEmpty);
    if (failure != null) {
      throw GoogleSignInException(
        code: failure!,
        description: 'SYNTHETIC_SECRET',
      );
    }
    return const AuthenticationResults(
      user: GoogleSignInUserData(
        email: 'synthetic@example.invalid',
        id: 'synthetic-oidc',
      ),
      authenticationTokens: AuthenticationTokenData(
        idToken: 'unused-synthetic-id-token',
      ),
    );
  }

  @override
  Future<AuthenticationResults?> attemptLightweightAuthentication(
    AttemptLightweightAuthenticationParameters params,
  ) async {
    fail('No debe iniciar autenticación ligera; puede mostrar UI');
  }

  @override
  Future<void> signOut(SignOutParams params) async {
    calls.add('signOut');
  }

  @override
  Future<void> disconnect(DisconnectParams params) async {
    fail('No debe revocar acceso remoto');
  }

  @override
  Future<void> clearAuthorizationToken(
    ClearAuthorizationTokenParams params,
  ) async {
    calls.add('clearToken');
  }

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
    ClientAuthorizationTokensForScopesParameters params,
  ) async {
    requests.add(params.request);
    if (!granted && !params.request.promptIfUnauthorized) return null;
    if (failure != null) {
      throw GoogleSignInException(
        code: failure!,
        description: 'SYNTHETIC_SECRET',
      );
    }
    return const ClientAuthorizationTokenData(
      accessToken: 'synthetic-access-token',
    );
  }
}

void main() {
  late NativeGoogle native;
  late GoogleSignInAuthorization adapter;
  setUpAll(() {
    native = NativeGoogle();
    GoogleSignInPlatform.instance = native;
  });
  setUp(() {
    native.calls.clear();
    native.requests.clear();
    native.failure = null;
    native.granted = true;
    adapter = GoogleSignInAuthorization(
      serverClientId: '123456789012-synthetic.apps.googleusercontent.com',
    );
  });
  test(
    'selección expresa usa SDK oficial y solo drive.file para autorización',
    () async {
      expect(
        await adapter.accessToken(interactive: true, selectAccount: true),
        'synthetic-access-token',
      );
      expect(native.calls, ['init', 'signOut', 'authenticate']);
      expect(native.requests.single.scopes, [driveFileScope]);
      expect(native.requests.single.userId, 'synthetic-oidc');
      expect(native.requests.single.promptIfUnauthorized, false);
    },
  );
  test(
    'consentimiento se pide solo cuando una acción expresa lo necesita',
    () async {
      native.granted = false;
      await adapter.accessToken(interactive: true, selectAccount: true);
      expect(native.requests.map((r) => r.promptIfUnauthorized), [false, true]);
      expect(
        native.requests.every(
          (r) => r.scopes.length == 1 && r.scopes.single == driveFileScope,
        ),
        true,
      );
    },
  );
  test(
    'renovar después de reiniciar no autentica ni abre consentimiento',
    () async {
      expect(
        await adapter.accessToken(interactive: false, selectAccount: false),
        'synthetic-access-token',
      );
      expect(native.calls.where((c) => c != 'init'), isEmpty);
      expect(native.requests.single.promptIfUnauthorized, false);
    },
  );
  test(
    'revocación durante renovación nunca abre recuperación interactiva',
    () async {
      native.granted = false;
      await expectLater(
        adapter.accessToken(interactive: false, selectAccount: false),
        throwsA(
          isA<DriveAccessFailure>().having(
            (e) => e.issue,
            'issue',
            DriveAccessIssue.credentialExpired,
          ),
        ),
      );
      expect(native.calls.where((c) => c != 'init'), isEmpty);
      expect(native.requests.length, 1);
    },
  );
  test(
    'renovar descarta token en caché antes de pedir otro silenciosamente',
    () async {
      await adapter.accessToken(interactive: true, selectAccount: true);
      native.calls.clear();
      native.requests.clear();
      await adapter.accessToken(interactive: false, selectAccount: false);
      expect(native.calls, ['clearToken']);
      expect(native.requests.single.promptIfUnauthorized, false);
    },
  );
  test('olvidar es local y una nueva conexión fuerza selección', () async {
    await adapter.accessToken(interactive: true, selectAccount: true);
    native.calls.clear();
    adapter.forget();
    expect(native.calls, isEmpty);
    await adapter.accessToken(interactive: true, selectAccount: true);
    expect(native.calls, ['signOut', 'authenticate']);
  });
  for (final entry in [
    (GoogleSignInExceptionCode.canceled, DriveAccessIssue.cancelled),
    (
      GoogleSignInExceptionCode.clientConfigurationError,
      DriveAccessIssue.clientConfigurationError,
    ),
    (
      GoogleSignInExceptionCode.providerConfigurationError,
      DriveAccessIssue.clientConfigurationError,
    ),
    (
      GoogleSignInExceptionCode.userMismatch,
      DriveAccessIssue.accountChangeRequired,
    ),
    (GoogleSignInExceptionCode.unknownError, DriveAccessIssue.unavailable),
  ]) {
    test('diagnóstico cerrado ${entry.$1} sin descripción privada', () async {
      native.failure = entry.$1;
      try {
        await adapter.accessToken(interactive: true, selectAccount: true);
        fail('Debe fallar');
      } on DriveAccessFailure catch (error) {
        expect(error.issue, entry.$2);
        expect(error.toString(), isNot(contains('SYNTHETIC_SECRET')));
      }
    });
  }
  test('serverClientId ausente falla antes de invocar la plataforma', () async {
    final invalid = GoogleSignInAuthorization(serverClientId: '');
    await expectLater(
      invalid.accessToken(interactive: true, selectAccount: true),
      throwsA(
        isA<DriveAccessFailure>().having(
          (e) => e.issue,
          'issue',
          DriveAccessIssue.clientConfigurationError,
        ),
      ),
    );
    expect(native.calls, isEmpty);
  });
  test(
    'otra composición reutiliza inicialización y no cambia el cliente del SDK',
    () async {
      await adapter.accessToken(interactive: false, selectAccount: false);
      expect(native.calls, isEmpty);
      final other = GoogleSignInAuthorization(
        serverClientId: '999999999999-other.apps.googleusercontent.com',
      );
      await expectLater(
        other.accessToken(interactive: true, selectAccount: true),
        throwsA(
          isA<DriveAccessFailure>().having(
            (e) => e.issue,
            'issue',
            DriveAccessIssue.clientConfigurationError,
          ),
        ),
      );
      expect(native.calls, isEmpty);
    },
  );
}
