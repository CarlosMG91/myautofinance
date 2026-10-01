import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myautofinance/features/synchronization/data/drive_metadata_credential.dart';
import 'package:myautofinance/features/synchronization/data/http_drive_metadata_client.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';

final start = DateTime.utc(2026, 10);

Matcher issue(DriveMetadataIssue value, {int? status}) =>
    isA<DriveMetadataFailure>()
        .having((e) => e.issue, 'issue', value)
        .having((e) => e.httpStatus, 'httpStatus', status);

Map<String, dynamic> metadata({String id = 'folder-a', bool folder = true}) => {
  'id': id,
  'name': folder ? 'Autofinance' : 'synthetic-copy.sqlite',
  'mimeType': folder ? driveFolderMimeType : 'application/octet-stream',
  'parents': ['root-id'],
  'trashed': false,
  if (!folder) ...{
    'modifiedTime': '2026-10-01T10:20:30.000Z',
    'size': '4096',
    'md5Checksum': '0123456789abcdef0123456789abcdef',
    'version': '18446744073709551615',
  },
};

http.Response json(
  Object data, {
  int status = 200,
  Map<String, String>? headers,
}) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8', ...?headers},
);

class Credentials implements DriveMetadataCredentialSource {
  int reads = 0;
  String? requestedAccount;
  Object? failure;
  Completer<DriveMetadataCredential>? pending;
  late DriveMetadataCredential value;

  @override
  Future<DriveMetadataCredential> readCredential({
    required String accountId,
  }) async {
    reads++;
    requestedAccount = accountId;
    if (failure != null) throw failure!;
    return pending == null ? value : pending!.future;
  }
}

/// Demuestra que el puerto de dominio es simulable sin HTTP ni OAuth.
class FakeMetadata implements DriveMetadataClient {
  @override
  Future<List<DriveFileMetadata>> listFiles({
    required String accountId,
    String? parentId,
    String? name,
    String? mimeType,
  }) async => [];

  @override
  Future<DriveFileMetadata> getFile({
    required String accountId,
    required String fileId,
  }) async => throw const DriveMetadataFailure(DriveMetadataIssue.notFound);

  @override
  Future<DriveFileMetadata> createAutofinanceFolder({
    required String accountId,
  }) async =>
      throw const DriveMetadataFailure(DriveMetadataIssue.permissionDenied);
}

void main() {
  late Credentials credentials;
  late DateTime now;
  late DriveMetadataClient client;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;
  late http.Client transport;

  void setCredential({
    String account = 'account-a',
    Set<String> scopes = const {driveFileScope},
    DateTime? until,
    String token = 'synthetic-access',
    DriveFolderBinding? folder,
  }) {
    credentials.value = DriveMetadataCredential(
      session: DriveSession(
        account: DriveAccount(permissionId: account),
        validUntil: until ?? start.add(const Duration(hours: 1)),
        grantedScopes: scopes,
        folder: folder,
      ),
      accessToken: token,
    );
  }

  Future<List<DriveFileMetadata>> list() =>
      client.listFiles(accountId: 'account-a');
  Future<DriveFileMetadata> get() =>
      client.getFile(accountId: 'account-a', fileId: 'folder-a');
  Future<DriveFileMetadata> create() =>
      client.createAutofinanceFolder(accountId: 'account-a');

  setUp(() {
    credentials = Credentials();
    now = start;
    requests = [];
    setCredential();
    respond = (_) async => json(metadata());
    transport = MockClient((request) {
      requests.add(request);
      return respond(request);
    });
    client = HttpDriveMetadataClient(
      client: transport,
      credentials: credentials,
      now: () => now,
    );
  });
  tearDown(() => transport.close());

  test(
    'constructor y puerto falso no inician red ni leen credenciales',
    () async {
      expect(requests, isEmpty);
      expect(credentials.reads, 0);
      final DriveMetadataClient fake = FakeMetadata();
      expect(await fake.listFiles(accountId: 'account-a'), isEmpty);
      await expectLater(
        fake.getFile(accountId: 'account-a', fileId: 'file-a'),
        throwsA(issue(DriveMetadataIssue.notFound)),
      );
    },
  );

  test('lista todas las páginas, incluidas páginas vacías, con filtros y campos', () async {
    respond = (request) async {
      final page = request.url.queryParameters['pageToken'];
      return json(switch (page) {
        null => {
          'files': [metadata()],
          'nextPageToken': 'opaque/+ token',
        },
        'opaque/+ token' => {
          'files': [],
          'incompleteSearch': false,
          'nextPageToken': 'last',
        },
        'last' => {
          'files': [metadata(id: 'copy-a', folder: false)],
        },
        _ => throw StateError('unexpected page'),
      });
    };
    final files = await client.listFiles(
      accountId: 'account-a',
      parentId: 'root',
      name: 'Autofinance',
      mimeType: driveFolderMimeType,
    );
    expect(files.map((f) => f.id), ['folder-a', 'copy-a']);
    expect(files.last.size, 4096);
    expect(files.last.modifiedTime, DateTime.utc(2026, 10, 1, 10, 20, 30));
    expect(files.last.version, '18446744073709551615');
    expect(files.last.md5Checksum, '0123456789abcdef0123456789abcdef');
    expect(files.first.size, isNull);
    expect(() => files.clear(), throwsUnsupportedError);
    expect(() => files.first.parents.clear(), throwsUnsupportedError);
    expect(requests, hasLength(3));
    expect(credentials.reads, 3);
    expect(credentials.requestedAccount, 'account-a');
    for (final request in requests) {
      expect(request.method, 'GET');
      expect(request.url.host, 'www.googleapis.com');
      expect(request.url.path, '/drive/v3/files');
      expect(
        request.url.queryParameters['q'],
        "trashed=false and 'root' in parents and name='Autofinance' and mimeType='$driveFolderMimeType'",
      );
      expect(request.url.queryParameters['spaces'], 'drive');
      expect(request.url.queryParameters['corpora'], 'user');
      expect(request.url.queryParameters['includeItemsFromAllDrives'], 'false');
      expect(request.url.queryParameters['pageSize'], '1000');
      expect(
        request.url.queryParameters['fields'],
        'nextPageToken,incompleteSearch,files(id,name,mimeType,parents,trashed,modifiedTime,size,md5Checksum,version)',
      );
      expect(request.headers['Authorization'], 'Bearer synthetic-access');
      expect(request.followRedirects, isFalse);
      expect(request.body, isEmpty);
      expect(request.url.queryParameters, isNot(contains('access_token')));
      expect(request.url.queryParameters, isNot(contains('alt')));
    }
  });

  test('escapa comillas y barras sin permitir inyección de consulta', () async {
    respond = (_) async => json({'files': []});
    await client.listFiles(
      accountId: 'account-a',
      parentId: "parent'\\",
      name: "a' or trashed=true or name='b\\",
    );
    expect(
      requests.single.url.queryParameters['q'],
      r"trashed=false and 'parent\'\\' in parents and name='a\' or trashed=true or name=\'b\\'",
    );
  });

  test('lista vacía no crea carpeta ni archivo ni renueva acceso', () async {
    respond = (_) async => json({'files': [], 'incompleteSearch': false});
    expect(await list(), isEmpty);
    expect(requests.single.method, 'GET');
    expect(credentials.reads, 1);
  });

  test('get codifica ID como un solo segmento y pide solo metadatos', () async {
    const id = 'file/with ?#%';
    respond = (_) async => json(metadata(id: id, folder: false));
    final file = await client.getFile(accountId: 'account-a', fileId: id);
    expect(file.id, id);
    final request = requests.single;
    expect(request.url.pathSegments, ['drive', 'v3', 'files', id]);
    expect(request.url.queryParameters.keys, ['fields']);
    expect(
      request.url.queryParameters['fields'],
      'id,name,mimeType,parents,trashed,modifiedTime,size,md5Checksum,version',
    );
  });

  for (final status in [200, 201]) {
    test(
      'create $status solo crea carpeta Autofinance visible en root',
      () async {
        respond = (_) async => json(metadata(), status: status);
        final folder = await create();
        expect(folder.mimeType, driveFolderMimeType);
        expect(folder.parents, ['root-id']);
        final request = requests.single;
        expect(request.method, 'POST');
        expect(request.url.path, '/drive/v3/files');
        expect(request.url.queryParameters, {
          'fields': 'id,name,mimeType,parents,trashed',
        });
        expect(jsonDecode(request.body), {
          'name': 'Autofinance',
          'mimeType': driveFolderMimeType,
          'parents': ['root'],
        });
        expect(request.headers['Content-Type'], startsWith('application/json'));
        expect(request.headers['Authorization'], 'Bearer synthetic-access');
        expect(request.followRedirects, isFalse);
      },
    );
  }

  final statuses = {
    401: DriveMetadataIssue.credentialExpired,
    403: DriveMetadataIssue.permissionDenied,
    404: DriveMetadataIssue.notFound,
    429: DriveMetadataIssue.rateLimited,
    500: DriveMetadataIssue.serverUnavailable,
    503: DriveMetadataIssue.serverUnavailable,
    400: DriveMetadataIssue.invalidRequest,
    302: DriveMetadataIssue.invalidRequest,
  };
  for (final entry in statuses.entries) {
    for (final operation in ['list', 'get', 'create']) {
      test(
        '$operation distingue HTTP ${entry.key} sin reintentos ni filtraciones',
        () async {
          respond = (_) async => http.Response(
            'private-response synthetic-access',
            entry.key,
            headers: {'location': 'https://untrusted.invalid/'},
          );
          try {
            await switch (operation) {
              'list' => list(),
              'get' => get(),
              _ => create(),
            };
            fail('Debe fallar');
          } on DriveMetadataFailure catch (failure) {
            expect(failure, issue(entry.value, status: entry.key));
            expect(failure.toString(), isNot(contains('private-response')));
            expect(failure.toString(), isNot(contains('synthetic-access')));
          }
          expect(requests, hasLength(1));
        },
      );
    }
  }

  for (final reason in [
    'rateLimitExceeded',
    'userRateLimitExceeded',
    'dailyLimitExceeded',
    'storageQuotaExceeded',
    'activeItemCreationLimitExceeded',
    'numChildrenInNonRootLimit',
    'myDriveHierarchyDepthLimit',
    'insufficientFilePermissions',
  ]) {
    test('403 clasifica $reason', () async {
      respond = (_) async => json({
        'error': {
          'errors': [
            {'reason': reason},
          ],
          'message': 'private-response',
        },
      }, status: 403);
      final expected = reason == 'insufficientFilePermissions'
          ? DriveMetadataIssue.permissionDenied
          : reason.contains('Rate') || reason == 'rateLimitExceeded'
          ? DriveMetadataIssue.rateLimited
          : DriveMetadataIssue.quotaExceeded;
      await expectLater(get(), throwsA(issue(expected, status: 403)));
    });
  }

  for (final value in [
    '120',
    'Thu, 01 Oct 2026 00:02:00 GMT',
    'Wed, 30 Sep 2026 00:00:00 GMT',
    'invalid',
    '-5',
  ]) {
    test('Retry-After $value queda como dato sin reintentar', () async {
      respond = (_) async =>
          json({}, status: 429, headers: {'retry-after': value});
      final expected = value == '120' || value.startsWith('Thu')
          ? const Duration(seconds: 120)
          : value.startsWith('Wed')
          ? Duration.zero
          : null;
      await expectLater(
        create(),
        throwsA(
          isA<DriveMetadataFailure>().having(
            (f) => f.retryAfter,
            'retryAfter',
            expected,
          ),
        ),
      );
      expect(requests, hasLength(1));
    });
  }

  for (final operation in ['list', 'get', 'create']) {
    test('$operation distingue fallo de conexión y sanea excepción', () async {
      respond = (_) async =>
          throw http.ClientException('synthetic-access private-url');
      await expectLater(switch (operation) {
        'list' => list(),
        'get' => get(),
        _ => create(),
      }, throwsA(issue(DriveMetadataIssue.networkFailure)));
      expect(requests, hasLength(1));
    });
    test('$operation distingue timeout sin reintentar', () async {
      final pending = Completer<http.Response>();
      respond = (_) => pending.future;
      client = HttpDriveMetadataClient(
        client: transport,
        credentials: credentials,
        now: () => now,
        requestTimeout: const Duration(milliseconds: 10),
      );
      await expectLater(switch (operation) {
        'list' => list(),
        'get' => get(),
        _ => create(),
      }, throwsA(issue(DriveMetadataIssue.requestTimeout)));
      expect(requests, hasLength(1));
      pending.complete(json(metadata()));
    });
  }

  test('timeout cubre también lectura del cuerpo HTTP', () async {
    final stream = StreamController<List<int>>();
    final streaming = MockClient.streaming(
      (_, _) async => http.StreamedResponse(stream.stream, 200),
    );
    client = HttpDriveMetadataClient(
      client: streaming,
      credentials: credentials,
      now: () => now,
      requestTimeout: const Duration(milliseconds: 10),
    );
    await expectLater(get(), throwsA(issue(DriveMetadataIssue.requestTimeout)));
    await stream.close();
    streaming.close();
  });

  for (final body in [
    'not-json',
    '[]',
    'null',
    '{}',
    '{"files":null}',
    '{"files":{}}',
    '{"files":[],"incompleteSearch":true}',
    '{"files":[],"incompleteSearch":"false"}',
    '{"files":[],"nextPageToken":42}',
    '{"files":[],"nextPageToken":""}',
    '{"files":[],"nextPageToken":null}',
  ]) {
    test('list rechaza respuesta incompleta $body', () async {
      respond = (_) async => http.Response(body, 200);
      await expectLater(
        list(),
        throwsA(issue(DriveMetadataIssue.incompleteResponse)),
      );
    });
  }

  test('paginación cíclica falla sin bucle ni lista parcial', () async {
    respond = (_) async => json({
      'files': [metadata()],
      'nextPageToken': 'cycle',
    });
    await expectLater(
      list(),
      throwsA(issue(DriveMetadataIssue.incompleteResponse)),
    );
    expect(requests, hasLength(2));
  });

  test('error en segunda página no devuelve resultados parciales', () async {
    respond = (_) async => requests.length == 1
        ? json({
            'files': [metadata()],
            'nextPageToken': 'next',
          })
        : json({}, status: 429);
    await expectLater(
      list(),
      throwsA(issue(DriveMetadataIssue.rateLimited, status: 429)),
    );
    expect(requests, hasLength(2));
  });

  test('caducidad entre páginas detiene acceso sin renovación', () async {
    respond = (_) async {
      now = start.add(const Duration(hours: 2));
      return json({
        'files': [metadata()],
        'nextPageToken': 'next',
      });
    };
    await expectLater(
      list(),
      throwsA(issue(DriveMetadataIssue.credentialExpired)),
    );
    expect(requests, hasLength(1));
  });

  test('cambio de cuenta entre páginas detiene acceso', () async {
    respond = (_) async {
      setCredential(account: 'account-b');
      return json({
        'files': [metadata()],
        'nextPageToken': 'next',
      });
    };
    await expectLater(
      list(),
      throwsA(issue(DriveMetadataIssue.accountChangeRequired)),
    );
    expect(requests, hasLength(1));
  });

  for (final key in ['id', 'name', 'mimeType', 'parents', 'trashed']) {
    test('get rechaza ausencia del campo requerido $key', () async {
      respond = (_) async => json(metadata()..remove(key));
      await expectLater(
        get(),
        throwsA(issue(DriveMetadataIssue.incompleteResponse)),
      );
    });
  }

  final malformed = <String, dynamic>{
    'id': 4,
    'name': '',
    'mimeType': null,
    'parents': [''],
    'trashed': 'false',
    'size': '-1',
    'modifiedTime': 'invalid-time',
    'md5Checksum': 'invalid-checksum',
    'version': 42,
  };
  for (final entry in malformed.entries) {
    test('get rechaza metadato inválido ${entry.key}', () async {
      respond = (_) async => json(metadata()..[entry.key] = entry.value);
      await expectLater(
        get(),
        throwsA(issue(DriveMetadataIssue.incompleteResponse)),
      );
    });
  }

  test('get rechaza ID distinto del solicitado', () async {
    respond = (_) async => json(metadata(id: 'other-file'));
    await expectLater(
      get(),
      throwsA(issue(DriveMetadataIssue.incompleteResponse)),
    );
  });
  test('get no expone archivos en papelera', () async {
    respond = (_) async => json(metadata()..['trashed'] = true);
    await expectLater(get(), throwsA(issue(DriveMetadataIssue.notFound)));
  });
  test('list rechaza elementos incompletos o en papelera', () async {
    for (final value in [null, {}, metadata()..['trashed'] = true]) {
      respond = (_) async => json({
        'files': [value],
      });
      await expectLater(
        list(),
        throwsA(issue(DriveMetadataIssue.incompleteResponse)),
      );
    }
  });
  test('create verifica identidad y tipo de carpeta devueltos', () async {
    for (final value in [
      metadata(folder: false),
      metadata()..['name'] = 'Other',
      metadata()..['trashed'] = true,
      metadata()..['parents'] = [],
    ]) {
      respond = (_) async => json(value);
      await expectLater(
        create(),
        throwsA(issue(DriveMetadataIssue.incompleteResponse)),
      );
    }
    expect(requests, hasLength(4));
  });

  for (final scopes in [
    <String>{},
    {'https://www.googleapis.com/auth/drive'},
    {driveFileScope, 'openid'},
  ]) {
    test('rechaza scope ausente, insuficiente o ampliado: $scopes', () async {
      setCredential(scopes: scopes);
      await expectLater(
        create(),
        throwsA(issue(DriveMetadataIssue.permissionDenied)),
      );
      expect(requests, isEmpty);
    });
  }
  test('rechaza cuenta o carpeta ajenas antes de HTTP', () async {
    setCredential(account: 'account-b');
    await expectLater(
      get(),
      throwsA(issue(DriveMetadataIssue.accountChangeRequired)),
    );
    setCredential(
      folder: DriveFolderBinding(accountId: 'account-b', folderId: 'folder-b'),
    );
    await expectLater(
      get(),
      throwsA(issue(DriveMetadataIssue.accountChangeRequired)),
    );
    expect(requests, isEmpty);
  });
  test('rechaza credencial caducada antes de HTTP', () async {
    setCredential(until: start);
    await expectLater(
      get(),
      throwsA(issue(DriveMetadataIssue.credentialExpired)),
    );
    expect(requests, isEmpty);
  });
  test('no conserva el token entre operaciones', () async {
    await get();
    setCredential(token: 'synthetic-second-access');
    await get();
    expect(
      requests.last.headers['Authorization'],
      'Bearer synthetic-second-access',
    );
    expect(credentials.reads, 2);
    expect(credentials.value.toString(), 'DriveMetadataCredential');
    expect((await get()).toString(), 'DriveFileMetadata');
  });
  test('rechaza token vacío o con inyección de cabeceras', () async {
    for (final token in [
      '',
      'token\r\nHeader: injected',
      'token with spaces',
    ]) {
      setCredential(token: token);
      await expectLater(
        get(),
        throwsA(issue(DriveMetadataIssue.invalidCredential)),
      );
    }
    expect(requests, isEmpty);
  });
  test(
    'errores del proveedor de credenciales están tipados y saneados',
    () async {
      final errors = <Object, DriveMetadataIssue>{
        const DriveAccessFailure(DriveAccessIssue.credentialExpired):
            DriveMetadataIssue.credentialExpired,
        const DriveAccessFailure(DriveAccessIssue.permissionDenied):
            DriveMetadataIssue.permissionDenied,
        const DriveAccessFailure(DriveAccessIssue.accountChangeRequired):
            DriveMetadataIssue.accountChangeRequired,
        const DriveAccessFailure(DriveAccessIssue.secureStorageFailure):
            DriveMetadataIssue.credentialUnavailable,
        StateError('private-credential'):
            DriveMetadataIssue.credentialUnavailable,
      };
      for (final entry in errors.entries) {
        credentials.failure = entry.key;
        await expectLater(get(), throwsA(issue(entry.value)));
      }
      expect(requests, isEmpty);
    },
  );
  test('timeout del proveedor no envía HTTP', () async {
    credentials.pending = Completer<DriveMetadataCredential>();
    client = HttpDriveMetadataClient(
      client: transport,
      credentials: credentials,
      now: () => now,
      requestTimeout: const Duration(milliseconds: 10),
    );
    await expectLater(get(), throwsA(issue(DriveMetadataIssue.requestTimeout)));
    credentials.pending!.complete(credentials.value);
    expect(requests, isEmpty);
  });
  test('parámetros vacíos fallan antes de pedir credenciales', () async {
    for (final action in [
      () => client.listFiles(accountId: ''),
      () => client.listFiles(accountId: 'account-a', parentId: ''),
      () => client.listFiles(accountId: 'account-a', name: ''),
      () => client.listFiles(accountId: 'account-a', mimeType: ''),
      () => client.getFile(accountId: 'account-a', fileId: ''),
      () => client.createAutofinanceFolder(accountId: ''),
    ]) {
      await expectLater(
        action(),
        throwsA(issue(DriveMetadataIssue.invalidRequest)),
      );
    }
    expect(credentials.reads, 0);
    expect(requests, isEmpty);
  });
}
