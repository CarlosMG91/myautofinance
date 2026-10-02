import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:myautofinance/features/synchronization/data/drive_metadata_credential.dart';
import 'package:myautofinance/features/synchronization/data/http_drive_transfer_client.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';

final class Credentials implements DriveMetadataCredentialSource {
  DriveMetadataCredential value = DriveMetadataCredential(
    session: DriveSession(
      account: DriveAccount(permissionId: 'account'),
      validUntil: DateTime.utc(2030),
      grantedScopes: const {driveFileScope},
    ),
    accessToken: 'synthetic-token',
  );
  @override
  Future<DriveMetadataCredential> readCredential({
    required String accountId,
  }) async => value;
}

final class Transport extends http.BaseClient {
  Transport(this.respond);
  final Future<http.StreamedResponse> Function(http.BaseRequest, List<int>)
  respond;
  final requests = <http.BaseRequest>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return respond(request, await request.finalize().toBytes());
  }
}

http.StreamedResponse response(
  int status, {
  Map<String, String> headers = const {},
  List<int> body = const [],
}) => http.StreamedResponse(Stream.value(body), status, headers: headers);

List<int> fileMetadata(int size) => utf8.encode(
  jsonEncode({
    'id': 'copy',
    'name': 'autofinance.sqlite',
    'mimeType': 'application/octet-stream',
    'parents': ['folder'],
    'trashed': false,
    'size': '$size',
    'version': '12',
    'modifiedTime': '2026-10-02T10:00:00Z',
    'appProperties': driveAutofinanceCopyProperties,
  }),
);

Matcher failure(DriveTransferIssue issue, [DriveMetadataIssue? remote]) =>
    isA<DriveTransferFailure>()
        .having((e) => e.issue, 'issue', issue)
        .having((e) => e.remoteFailure?.issue, 'remote', remote);

void main() {
  late Directory temp;
  late File source;
  late Credentials credentials;
  late DriveTransferCancellation cancellation;
  late Transport transport;
  late HttpDriveTransferClient client;
  const size = HttpDriveTransferClient.chunkBytes * 2 + 17;
  const session =
      'https://www.googleapis.com/upload/drive/v3/files?upload_id=synthetic';

  void use(
    Future<http.StreamedResponse> Function(http.BaseRequest, List<int>)
    respond, {
    Duration timeout = const Duration(seconds: 2),
  }) {
    transport = Transport(respond);
    client = HttpDriveTransferClient(
      client: transport,
      credentials: credentials,
      now: () => DateTime.utc(2026, 10, 2),
      requestTimeout: timeout,
    );
  }

  Future<DriveFileMetadata> upload({
    Future<void> Function()? gate,
    void Function(DriveTransferProgress)? progress,
    String? fileId = 'copy',
  }) => client.upload(
    accountId: 'account',
    folderId: 'folder',
    fileId: fileId,
    sourcePath: source.path,
    cancellation: cancellation,
    beforeCommit: gate ?? () async {},
    onProgress: progress,
  );
  Future<DriveDownloadCandidate> download({
    int bytes = 3,
    void Function(DriveTransferProgress)? progress,
  }) => client.download(
    accountId: 'account',
    fileId: 'copy',
    expectedBytes: bytes,
    temporaryDirectory: temp.path,
    cancellation: cancellation,
    onProgress: progress,
  );
  Future<http.StreamedResponse> success(
    http.BaseRequest request,
    List<int> body,
  ) async {
    if (request.method != 'PUT') {
      return response(200, headers: {'location': session});
    }
    final range = request.headers['Content-Range']!;
    if (range.endsWith('${size - 1}/$size')) {
      return response(200, body: fileMetadata(size));
    }
    final end = range.split('-')[1].split('/')[0];
    return response(308, headers: {'range': 'bytes=0-$end'});
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('transfer-test-');
    source = File('${temp.path}/snapshot.synthetic');
    await source.writeAsBytes(List.generate(size, (i) => i % 251));
    credentials = Credentials();
    cancellation = DriveTransferCancellation();
    use(success);
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test(
    'rangos de 256 KiB, contenido, acuses y gate antes de último bloque',
    () async {
      final progress = <int>[];
      final received = <int>[];
      use((request, body) async {
        if (request.method == 'PUT') received.addAll(body);
        expect(request.followRedirects, false);
        return success(request, body);
      });
      var gated = false;
      final file = await upload(
        gate: () async {
          expect(transport.requests.length, 3);
          gated = true;
        },
        progress: (p) => progress.add(p.bytes),
      );
      expect(file.version, '12');
      expect(gated, true);
      expect(received, await source.readAsBytes());
      expect(progress.last, size);
      expect(transport.requests.map((r) => r.method), [
        'PATCH',
        'PUT',
        'PUT',
        'PUT',
      ]);
      expect(
        transport.requests[1].headers['Content-Range'],
        'bytes 0-262143/$size',
      );
      expect(
        transport.requests[2].headers['Content-Range'],
        'bytes 262144-524287/$size',
      );
    },
  );
  test(
    'primera copia incluye nombre, padre y marca sin archivo vacío',
    () async {
      use((request, body) async {
        if (request.method == 'POST') {
          final meta = jsonDecode(utf8.decode(body)) as Map;
          expect(meta['name'], driveAutofinanceCopyName);
          expect(meta['parents'], ['folder']);
          expect(meta['appProperties'], driveAutofinanceCopyProperties);
        }
        return success(request, body);
      });
      await upload(fileId: null);
      expect(transport.requests.first.method, 'POST');
    },
  );
  test('cancelar antes de empezar no hace red', () async {
    cancellation.cancel();
    await expectLater(upload(), throwsA(failure(DriveTransferIssue.cancelled)));
    await expectLater(
      download(),
      throwsA(failure(DriveTransferIssue.cancelled)),
    );
    expect(transport.requests, isEmpty);
  });
  test('cancelar en gate conserva los bloques sin publicar', () async {
    await expectLater(
      upload(
        gate: () async {
          cancellation.cancel();
        },
      ),
      throwsA(failure(DriveTransferIssue.cancelled)),
    );
    expect(transport.requests.length, 3);
  });
  test('cancelar gate pendiente termina sin último PUT', () async {
    final entered = Completer<void>();
    final pending = upload(
      gate: () {
        entered.complete();
        return Completer<void>().future;
      },
    );
    final check = expectLater(
      pending,
      throwsA(failure(DriveTransferIssue.cancelled)),
    );
    await entered.future;
    cancellation.cancel();
    await check;
    expect(transport.requests.length, 3);
  });
  test('divergencia del gate detiene publicación', () async {
    await expectLater(
      upload(
        gate: () async {
          throw StateError('synthetic-divergence');
        },
      ),
      throwsStateError,
    );
    expect(transport.requests.length, 3);
  });
  test('Range incoherente detiene subida sin retry', () async {
    use(
      (r, b) async => r.method == 'PUT'
          ? response(308, headers: {'range': 'bytes=0-2'})
          : await success(r, b),
    );
    await expectLater(
      upload(),
      throwsA(failure(DriveTransferIssue.invalidResponse)),
    );
    expect(transport.requests.length, 2);
  });
  test('location ajena no recibe credenciales', () async {
    use(
      (r, b) async =>
          response(200, headers: {'location': 'https://example.com/private'}),
    );
    await expectLater(
      upload(),
      throwsA(failure(DriveTransferIssue.invalidResponse)),
    );
    expect(transport.requests.length, 1);
  });
  test('respuesta final ilegible es ambigua', () async {
    use(
      (r, b) async =>
          r.headers['Content-Range']?.endsWith('${size - 1}/$size') == true
          ? response(200, body: utf8.encode('private-invalid'))
          : await success(r, b),
    );
    await expectLater(
      upload(),
      throwsA(failure(DriveTransferIssue.ambiguousResponse)),
    );
  });
  test(
    'corte en último PUT es ambiguo; repetición solo por otra llamada',
    () async {
      use((r, b) async {
        if (r.headers['Content-Range']?.endsWith('${size - 1}/$size') == true) {
          throw const SocketException('private');
        }
        return success(r, b);
      });
      await expectLater(
        upload(),
        throwsA(
          failure(
            DriveTransferIssue.ambiguousResponse,
            DriveMetadataIssue.networkFailure,
          ),
        ),
      );
      expect(transport.requests.length, 4);
      use(success);
      await upload();
      expect(transport.requests.length, 4);
    },
  );
  test('cancelar durante commit devuelve ambiguo', () async {
    use((r, b) async {
      if (r.headers['Content-Range']?.endsWith('${size - 1}/$size') == true) {
        cancellation.cancel();
        return Completer<http.StreamedResponse>().future;
      }
      return success(r, b);
    });
    await expectLater(
      upload(),
      throwsA(failure(DriveTransferIssue.ambiguousResponse)),
    );
  });
  for (final entry in {
    401: DriveMetadataIssue.credentialExpired,
    403: DriveMetadataIssue.permissionDenied,
    404: DriveMetadataIssue.notFound,
    429: DriveMetadataIssue.rateLimited,
    503: DriveMetadataIssue.serverUnavailable,
  }.entries) {
    test('HTTP ${entry.key} tipado en download y upload', () async {
      use((r, b) async => response(entry.key));
      await expectLater(
        download(),
        throwsA(failure(DriveTransferIssue.remoteFailure, entry.value)),
      );
      await expectLater(
        upload(),
        throwsA(failure(DriveTransferIssue.remoteFailure, entry.value)),
      );
      expect(await temp.list().length, 1);
    });
  }
  test('cuota, retryAfter y representación sin secretos', () async {
    use(
      (r, b) async => response(
        403,
        body: utf8.encode(
          jsonEncode({
            'error': {
              'errors': [
                {'reason': 'storageQuotaExceeded'},
              ],
            },
          }),
        ),
      ),
    );
    await expectLater(
      download(),
      throwsA(
        failure(
          DriveTransferIssue.remoteFailure,
          DriveMetadataIssue.quotaExceeded,
        ),
      ),
    );
    use((r, b) async => response(429, headers: {'retry-after': '7'}));
    try {
      await download();
      fail('expected failure');
    } on DriveTransferFailure catch (e) {
      expect(e.remoteFailure!.retryAfter, const Duration(seconds: 7));
      expect(e.toString(), isNot(contains('synthetic-token')));
    }
  });
  test('timeout aborta y no publica parcial', () async {
    use(
      (r, b) => Completer<http.StreamedResponse>().future,
      timeout: const Duration(milliseconds: 20),
    );
    await expectLater(
      download(),
      throwsA(
        failure(
          DriveTransferIssue.remoteFailure,
          DriveMetadataIssue.requestTimeout,
        ),
      ),
    );
    expect(await temp.list().length, 1);
    await (transport.requests.single as http.Abortable).abortTrigger;
  });
  test('download streaming a candidata sin sustituir activa', () async {
    use(
      (r, b) async => http.StreamedResponse(
        Stream.fromIterable([
          [1],
          [2, 3],
        ]),
        200,
      ),
    );
    final progress = <int>[];
    final candidate = await download(progress: (p) => progress.add(p.bytes));
    expect(await File(candidate.path).readAsBytes(), [1, 2, 3]);
    expect(candidate.path, endsWith('.part'));
    expect(progress, [0, 1, 3, 3]);
    expect(await source.length(), size);
  });
  test('cancelación durante streaming limpia staging', () async {
    use(
      (r, b) async => http.StreamedResponse(
        Stream.fromIterable([
          [1],
          [2, 3],
        ]),
        200,
      ),
    );
    await expectLater(
      download(
        progress: (p) {
          if (p.bytes == 1) cancellation.cancel();
        },
      ),
      throwsA(failure(DriveTransferIssue.cancelled)),
    );
    expect(await temp.list().length, 1);
  });
  for (final body in [
    [1, 2],
    [1, 2, 3, 4],
  ]) {
    test('longitud ${body.length} inesperada elimina parcial', () async {
      use((r, b) async => response(200, body: body));
      await expectLater(
        download(),
        throwsA(failure(DriveTransferIssue.invalidResponse)),
      );
      expect(await temp.list().length, 1);
    });
  }
  test(
    'red durante cuerpo elimina parcial y admite repetición manual',
    () async {
      use(
        (r, b) async => http.StreamedResponse(
          Stream<List<int>>.multi((s) {
            s.add([1]);
            s.addError(const SocketException('private'));
            s.close();
          }),
          200,
        ),
      );
      await expectLater(
        download(),
        throwsA(
          failure(
            DriveTransferIssue.remoteFailure,
            DriveMetadataIssue.networkFailure,
          ),
        ),
      );
      expect(await temp.list().length, 1);
      use((r, b) async => response(200, body: [1, 2, 3]));
      expect((await download()).bytes, 3);
    },
  );
  test('credencial caducada no transfiere ni renueva', () async {
    credentials.value = DriveMetadataCredential(
      session: DriveSession(
        account: DriveAccount(permissionId: 'account'),
        validUntil: DateTime.utc(2020),
        grantedScopes: const {driveFileScope},
      ),
      accessToken: 'synthetic-token',
    );
    await expectLater(
      upload(),
      throwsA(
        failure(
          DriveTransferIssue.remoteFailure,
          DriveMetadataIssue.credentialExpired,
        ),
      ),
    );
    expect(transport.requests, isEmpty);
  });
  test('timeout durante streaming aborta y elimina candidata', () async {
    use(
      (r, b) async =>
          http.StreamedResponse(StreamController<List<int>>().stream, 200),
      timeout: const Duration(milliseconds: 20),
    );
    await expectLater(
      download(),
      throwsA(
        failure(
          DriveTransferIssue.remoteFailure,
          DriveMetadataIssue.requestTimeout,
        ),
      ),
    );
    expect(await temp.list().length, 1);
    await (transport.requests.single as http.Abortable).abortTrigger;
  });
  test('cancelación esperando cabeceras aborta; respuesta tardía no recrea parcial', () async {
    final entered = Completer<void>();
    final headers = Completer<http.StreamedResponse>();
    use((r, b) {
      entered.complete();
      return headers.future;
    });
    final pending = expectLater(
      download(),
      throwsA(failure(DriveTransferIssue.cancelled)),
    );
    await entered.future;
    cancellation.cancel();
    await pending;
    await (transport.requests.single as http.Abortable).abortTrigger;
    headers.complete(response(200, body: [1, 2, 3]));
    await Future<void>.delayed(Duration.zero);
    expect(await temp.list().length, 1);
  });
  test('timeout final es ambiguo y preserva motivo', () async {
    use((r, b) async {
      if (r.headers['Content-Range']?.endsWith('${size - 1}/$size') == true) {
        return Completer<http.StreamedResponse>().future;
      }
      return success(r, b);
    }, timeout: const Duration(milliseconds: 50));
    await expectLater(
      upload(),
      throwsA(
        failure(
          DriveTransferIssue.ambiguousResponse,
          DriveMetadataIssue.requestTimeout,
        ),
      ),
    );
    expect(transport.requests.length, 4);
  });
  test(
    '5xx al publicar es ambiguo, 401 exige renovar explícitamente',
    () async {
      for (final status in [503, 401]) {
        use(
          (r, b) async =>
              r.headers['Content-Range']?.endsWith('${size - 1}/$size') == true
              ? response(status)
              : await success(r, b),
        );
        await expectLater(
          upload(),
          throwsA(
            failure(
              status == 503
                  ? DriveTransferIssue.ambiguousResponse
                  : DriveTransferIssue.remoteFailure,
              status == 503
                  ? DriveMetadataIssue.serverUnavailable
                  : DriveMetadataIssue.credentialExpired,
            ),
          ),
        );
        expect(transport.requests.length, 4);
      }
    },
  );
  test('error de disco y origen vacío son tipados sin red', () async {
    await source.delete();
    await expectLater(
      upload(),
      throwsA(failure(DriveTransferIssue.localIoFailure)),
    );
    await source.writeAsBytes([]);
    await expectLater(
      upload(),
      throwsA(failure(DriveTransferIssue.invalidRequest)),
    );
    await expectLater(
      client.download(
        accountId: 'account',
        fileId: 'copy',
        expectedBytes: 3,
        temporaryDirectory: source.path,
        cancellation: cancellation,
      ),
      throwsA(failure(DriveTransferIssue.localIoFailure)),
    );
    expect(transport.requests, isEmpty);
  });
  test('cuenta distinta no transfiere credenciales', () async {
    credentials.value = DriveMetadataCredential(
      session: DriveSession(
        account: DriveAccount(permissionId: 'other'),
        validUntil: DateTime.utc(2030),
        grantedScopes: const {driveFileScope},
      ),
      accessToken: 'synthetic-token',
    );
    await expectLater(
      download(),
      throwsA(
        failure(
          DriveTransferIssue.remoteFailure,
          DriveMetadataIssue.accountChangeRequired,
        ),
      ),
    );
    expect(transport.requests, isEmpty);
  });
  test(
    'nueva llamada tras cancelar usa otra sesión, sin reintento oculto',
    () async {
      await expectLater(
        upload(
          gate: () async {
            cancellation.cancel();
          },
        ),
        throwsA(failure(DriveTransferIssue.cancelled)),
      );
      expect(transport.requests.length, 3);
      cancellation = DriveTransferCancellation();
      await upload();
      expect(transport.requests.length, 7);
      expect(transport.requests.where((r) => r.method == 'PATCH').length, 2);
    },
  );
}
