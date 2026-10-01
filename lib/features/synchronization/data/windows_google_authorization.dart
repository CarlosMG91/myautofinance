import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../domain/drive_access.dart';

/// Datos transitorios internos: nunca se exportan por la entrada de dominio.
final class WindowsAuthorizationCode {
  const WindowsAuthorizationCode(this.code, this.verifier, this.redirectUri);
  final String code;
  final String verifier;
  final Uri redirectUri;
  @override
  String toString() => 'WindowsAuthorizationCode';
}

abstract interface class WindowsGoogleAuthorization {
  Future<WindowsAuthorizationCode> authorize({
    required bool selectAccount,
    required bool requireConsent,
    String? loginHint,
  });
  void cancel();
}

final class _Callback {
  const _Callback({this.code, this.issue});
  final String? code;
  final DriveAccessIssue? issue;
}

/// Navegador del sistema y receptor privado por intento; nunca WebView.
final class LoopbackGoogleAuthorization implements WindowsGoogleAuthorization {
  LoopbackGoogleAuthorization({
    required this.clientId,
    Future<void> Function(Uri)? openBrowser,
    Future<HttpServer> Function()? bind,
    this.timeout = const Duration(minutes: 3),
  }) : _openBrowser = openBrowser ?? _systemBrowser,
       _bind = bind ?? (() => HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final String clientId;
  final Duration timeout;
  final Future<void> Function(Uri) _openBrowser;
  final Future<HttpServer> Function() _bind;
  Completer<_Callback>? _pending;

  static Future<void> _systemBrowser(Uri uri) async {
    try {
      await const MethodChannel('autofinance/windows_drive')
          .invokeMethod<void>('openBrowser', uri.toString());
    } catch (_) {
      throw const DriveAccessFailure(DriveAccessIssue.unavailable);
    }
  }

  static String _random() {
    final random = Random.secure();
    return base64Url
        .encode(List.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  static Future<void> _reply(HttpResponse response, int status) async {
    try {
      response
        ..statusCode = status
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
        ..headers.set('Referrer-Policy', 'no-referrer')
        ..headers.set('Content-Security-Policy', "default-src 'none'")
        ..headers.contentType = ContentType.text
        ..write('Autofinance: vuelve a la aplicación.');
      await response.close().timeout(const Duration(seconds: 2));
    } catch (_) {
      // Un navegador/socket cerrado no debe producir una excepción sin sanear.
    }
  }

  @override
  void cancel() {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.complete(const _Callback(issue: DriveAccessIssue.cancelled));
    }
  }

  @override
  Future<WindowsAuthorizationCode> authorize({
    required bool selectAccount,
    required bool requireConsent,
    String? loginHint,
  }) async {
    if (_pending != null) {
      throw const DriveAccessFailure(DriveAccessIssue.operationInProgress);
    }
    if (!RegExp(r'^\d+-[a-z0-9]+\.apps\.googleusercontent\.com$')
        .hasMatch(clientId)) {
      throw const DriveAccessFailure(DriveAccessIssue.clientConfigurationError);
    }
    final pending = _pending = Completer<_Callback>();
    HttpServer? server;
    StreamSubscription<HttpRequest>? subscription;
    Timer? timer;
    try {
      try {
        server = await _bind();
      } catch (_) {
        throw const DriveAccessFailure(DriveAccessIssue.loopbackUnavailable);
      }
      final receiver = server;
      final redirect = Uri.parse('http://127.0.0.1:${receiver.port}/');
      final state = _random();
      final verifier = _random();
      final challenge = base64Url
          .encode(sha256.convert(ascii.encode(verifier)).bytes)
          .replaceAll('=', '');
      timer = Timer(timeout, () {
        if (!pending.isCompleted) {
          pending.complete(
            const _Callback(issue: DriveAccessIssue.authorizationTimeout),
          );
        }
      });
      var accepting = true;
      subscription = receiver.listen(
        (request) async {
          // Ignorar peticiones ajenas: no pueden consumir el intento legítimo.
          Map<String, List<String>> query;
          try {
            query = request.uri.queryParametersAll;
          } catch (_) {
            query = {};
          }
          final ours =
              request.method == 'GET' &&
              request.uri.path == '/' &&
              request.headers[HttpHeaders.hostHeader]?.length == 1 &&
              request.headers[HttpHeaders.hostHeader]!.single ==
                  redirect.authority &&
              query['state']?.length == 1 &&
              query['state']!.single == state &&
              !pending.isCompleted &&
              accepting;
          var status = HttpStatus.badRequest;
          _Callback? callback;
          if (ours) {
            accepting = false;
            final code = query['code'];
            final error = query['error'];
            if (code?.length == 1 && code!.single.isNotEmpty && error == null) {
              callback = _Callback(code: code.single);
              status = HttpStatus.ok;
            } else if (error?.length == 1 && code == null) {
              callback = _Callback(
                issue: error!.single == 'access_denied'
                    ? DriveAccessIssue.permissionDenied
                    : DriveAccessIssue.clientConfigurationError,
              );
              status = HttpStatus.ok;
            } else {
              callback = const _Callback(
                issue: DriveAccessIssue.invalidSession,
              );
            }
          }
          await _reply(request.response, status);
          if (callback != null && !pending.isCompleted) {
            pending.complete(callback);
          }
        },
        onError: (Object _) {
          if (!pending.isCompleted) {
            pending.complete(
              const _Callback(issue: DriveAccessIssue.loopbackUnavailable),
            );
          }
        },
      );
      final prompt = [
        if (selectAccount) 'select_account',
        if (requireConsent) 'consent',
      ];
      final uri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': clientId,
        'redirect_uri': redirect.toString(),
        'response_type': 'code',
        'scope': driveFileScope,
        'access_type': 'offline',
        'state': state,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        if (prompt.isNotEmpty) 'prompt': prompt.join(' '),
        if (loginHint != null && !selectAccount) 'login_hint': loginHint,
      });
      if (!pending.isCompleted) {
        await Future.any([_openBrowser(uri), pending.future.then((_) {})]);
      }
      final callback = await pending.future;
      if (callback.issue != null) throw DriveAccessFailure(callback.issue!);
      return WindowsAuthorizationCode(callback.code!, verifier, redirect);
    } on DriveAccessFailure {
      rethrow;
    } catch (_) {
      throw const DriveAccessFailure(DriveAccessIssue.unavailable);
    } finally {
      timer?.cancel();
      // Cerrar sockets incluso si el navegador falla o el usuario cancela.
      await server?.close(force: true);
      await subscription?.cancel();
      _pending = null;
    }
  }
}
