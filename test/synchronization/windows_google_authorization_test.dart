import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/features/synchronization/data/windows_google_authorization.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';

const clientId = '123-synthetic.apps.googleusercontent.com';
Matcher issue(DriveAccessIssue value) =>
    isA<DriveAccessFailure>().having((e) => e.issue, 'issue', value);

Future<int> callback(
  Uri authorization,
  Map<String, dynamic> query, {
  String path = '/',
  String method = 'GET',
}) async {
  final uri = Uri.parse(authorization.queryParameters['redirect_uri']!)
      .replace(path: path, queryParameters: query);
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, uri);
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

Future<void> closed(Uri uri) async {
  final redirect = Uri.parse(uri.queryParameters['redirect_uri']!);
  final server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    redirect.port,
  );
  await server.close(force: true);
}

void main() {
  test('Sistema recibe Google HTTPS, scope único, state y PKCE S256; cierra al éxito', () async {
    late Uri opened;
    final auth = LoopbackGoogleAuthorization(
      clientId: clientId,
      openBrowser: (uri) async {
        opened = uri;
        await callback(uri, {
          'state': uri.queryParameters['state']!,
          'code': 'synthetic-code',
        });
      },
    );
    final code = await auth.authorize(
      selectAccount: true,
      requireConsent: true,
    );
    expect(opened.host, 'accounts.google.com');
    expect(opened.scheme, 'https');
    expect(opened.queryParameters['scope'], driveFileScope);
    expect(opened.queryParameters['access_type'], 'offline');
    expect(opened.queryParameters['prompt'], 'select_account consent');
    expect(opened.queryParameters['code_challenge_method'], 'S256');
    expect(opened.queryParameters['state']!.length, 43);
    expect(code.verifier.length, 43);
    expect(code.code, 'synthetic-code');
    expect(code.redirectUri.host, '127.0.0.1');
    expect(code.redirectUri.port, isPositive);
    expect(
      opened.queryParameters['code_challenge'],
      base64Url
          .encode(sha256.convert(ascii.encode(code.verifier)).bytes)
          .replaceAll('=', ''),
    );
    expect(opened.queryParameters, isNot(contains('client_secret')));
    expect(code.toString(), 'WindowsAuthorizationCode');
    await closed(opened);
  });

  test('State erróneo/ausente/duplicado, ruta y método ajenos no consumen el intento', () async {
    late Uri opened;
    final auth = LoopbackGoogleAuthorization(
      clientId: clientId,
      openBrowser: (uri) async {
        opened = uri;
        final state = uri.queryParameters['state']!;
        expect(
          await callback(uri, {'state': 'foreign', 'code': 'foreign'}),
          400,
        );
        expect(await callback(uri, {'code': 'foreign'}), 400);
        expect(
          await callback(uri, {
            'state': [state, state],
            'code': 'foreign',
          }),
          400,
        );
        expect(
          await callback(uri, {
            'state': state,
            'code': 'foreign',
          }, path: '/foreign'),
          400,
        );
        expect(
          await callback(uri, {
            'state': state,
            'code': 'foreign',
          }, method: 'POST'),
          400,
        );
        await callback(uri, {'state': state, 'code': 'accepted'});
      },
    );
    expect(
      (await auth.authorize(selectAccount: false, requireConsent: false)).code,
      'accepted',
    );
    expect(opened.queryParameters, isNot(contains('prompt')));
    await closed(opened);
  });

  test(
    'Dos instancias no aceptan el state de la otra y usan puertos diferentes',
    () async {
      final openedA = Completer<Uri>();
      final openedB = Completer<Uri>();
      final a = LoopbackGoogleAuthorization(
        clientId: clientId,
        openBrowser: (u) async {
          openedA.complete(u);
        },
      );
      final b = LoopbackGoogleAuthorization(
        clientId: clientId,
        openBrowser: (u) async {
          openedB.complete(u);
        },
      );
      final resultA = a.authorize(selectAccount: true, requireConsent: true);
      final resultB = b.authorize(selectAccount: true, requireConsent: true);
      final ua = await openedA.future;
      final ub = await openedB.future;
      expect(
        ua.queryParameters['redirect_uri'],
        isNot(ub.queryParameters['redirect_uri']),
      );
      expect(ua.queryParameters['state'], isNot(ub.queryParameters['state']));
      expect(
        await callback(ua, {
          'state': ub.queryParameters['state']!,
          'code': 'wrong',
        }),
        400,
      );
      await callback(ua, {'state': ua.queryParameters['state']!, 'code': 'a'});
      await callback(ub, {'state': ub.queryParameters['state']!, 'code': 'b'});
      expect((await resultA).code, 'a');
      expect((await resultB).code, 'b');
      await closed(ua);
      await closed(ub);
    },
  );

  for (final query in [
    <String, dynamic>{
      'code': ['one', 'two'],
    },
    {'code': 'one', 'error': 'access_denied'},
    <String, dynamic>{},
  ]) {
    test('Callback ambiguo se rechaza y cierra: $query', () async {
      late Uri opened;
      final auth = LoopbackGoogleAuthorization(
        clientId: clientId,
        openBrowser: (u) async {
          opened = u;
          await callback(u, {'state': u.queryParameters['state']!, ...query});
        },
      );
      await expectLater(
        auth.authorize(selectAccount: false, requireConsent: false),
        throwsA(issue(DriveAccessIssue.invalidSession)),
      );
      await closed(opened);
    });
  }

  test('Denegar se distingue de cancelar y cierra', () async {
    late Uri opened;
    final auth = LoopbackGoogleAuthorization(
      clientId: clientId,
      openBrowser: (u) async {
        opened = u;
        await callback(u, {
          'state': u.queryParameters['state']!,
          'error': 'access_denied',
        });
      },
    );
    await expectLater(
      auth.authorize(selectAccount: false, requireConsent: false),
      throwsA(issue(DriveAccessIssue.permissionDenied)),
    );
    await closed(opened);
  });

  test('Cancelación explícita cierra incluso con lanzamiento pendiente; se puede reintentar', () async {
    final opened = Completer<Uri>();
    final never = Completer<void>();
    final auth = LoopbackGoogleAuthorization(
      clientId: clientId,
      openBrowser: (u) {
        opened.complete(u);
        return never.future;
      },
    );
    final result = auth.authorize(selectAccount: false, requireConsent: false);
    final assertion = expectLater(
      result,
      throwsA(issue(DriveAccessIssue.cancelled)),
    );
    final uri = await opened.future;
    auth.cancel();
    await assertion;
    await closed(uri);
    auth.cancel();
  });

  test('Timeout y fallo del navegador cierran; errores no incluyen el texto externo', () async {
    for (final fails in [false, true]) {
      late Uri opened;
      final auth = LoopbackGoogleAuthorization(
        clientId: clientId,
        timeout: const Duration(milliseconds: 50),
        openBrowser: (u) async {
          opened = u;
          if (fails) throw StateError('synthetic-private-message');
        },
      );
      await expectLater(
        auth.authorize(selectAccount: false, requireConsent: false),
        throwsA(
          issue(
            fails
                ? DriveAccessIssue.unavailable
                : DriveAccessIssue.authorizationTimeout,
          ),
        ),
      );
      await closed(opened);
    }
  });

  test('Puerto ocupado se notifica y no abre navegador; el binding productivo pide puerto cero', () async {
    final occupied = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var launches = 0;
    final auth = LoopbackGoogleAuthorization(
      clientId: clientId,
      bind: () => HttpServer.bind(InternetAddress.loopbackIPv4, occupied.port),
      openBrowser: (_) async {
        launches++;
      },
    );
    await expectLater(
      auth.authorize(selectAccount: false, requireConsent: false),
      throwsA(issue(DriveAccessIssue.loopbackUnavailable)),
    );
    expect(launches, 0);
    await occupied.close(force: true);
  });

  test('Exclusión de operaciones y clientId inválido', () async {
    final opened = Completer<Uri>();
    final auth = LoopbackGoogleAuthorization(
      clientId: clientId,
      openBrowser: (u) async {
        opened.complete(u);
      },
    );
    final first = auth.authorize(selectAccount: false, requireConsent: false);
    final assertion = expectLater(
      first,
      throwsA(issue(DriveAccessIssue.cancelled)),
    );
    final uri = await opened.future;
    await expectLater(
      auth.authorize(selectAccount: false, requireConsent: false),
      throwsA(issue(DriveAccessIssue.operationInProgress)),
    );
    auth.cancel();
    await assertion;
    await closed(uri);
    final invalid = LoopbackGoogleAuthorization(clientId: '');
    await expectLater(
      invalid.authorize(selectAccount: true, requireConsent: true),
      throwsA(issue(DriveAccessIssue.clientConfigurationError)),
    );
  });
}
