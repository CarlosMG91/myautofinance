import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myautofinance/features/synchronization/data/drive_metadata_credential.dart';
import 'package:myautofinance/features/synchronization/data/http_drive_metadata_client.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';

final _now = DateTime.utc(2026, 10, 2);
DriveFolderBinding _binding([String account = 'account-a']) =>
    DriveFolderBinding(accountId: account, folderId: 'folder-$account');
DriveCopyBinding _known({String account = 'account-a', String? folderId}) =>
    DriveCopyBinding(
      accountId: account,
      folderId: folderId ?? _binding(account).folderId,
      fileId: 'copy-a',
    );
DriveSession _grant({String account = 'account-a', bool folder = true}) =>
    DriveSession(
      account: DriveAccount(permissionId: account),
      validUntil: _now.add(const Duration(hours: 1)),
      grantedScopes: {driveFileScope},
      folder: folder ? _binding(account) : null,
    );
DriveFileMetadata _folder({
  String account = 'account-a',
  String? id,
  String parent = 'actual-root',
  bool trashed = false,
  String mimeType = driveFolderMimeType,
  Map<String, String> properties = driveAutofinanceFolderProperties,
}) => DriveFileMetadata(
  id: id ?? _binding(account).folderId,
  name: 'Autofinance',
  mimeType: mimeType,
  parents: [parent],
  trashed: trashed,
  appProperties: properties,
);
DriveFileMetadata _copy({
  String id = 'copy-a',
  String name = driveAutofinanceCopyName,
  String parent = 'folder-account-a',
  String mimeType = 'application/x-sqlite3',
  bool trashed = false,
  String? version = '42',
  bool modifiedTime = true,
  Map<String, String> properties = driveAutofinanceCopyProperties,
}) => DriveFileMetadata(
  id: id,
  name: name,
  mimeType: mimeType,
  parents: [parent],
  trashed: trashed,
  appProperties: properties,
  version: version,
  modifiedTime: modifiedTime ? _now : null,
);

final class _Provider implements DriveSessionProvider {
  DriveSession? local = _grant();
  String nextAccount = 'account-b';
  final calls = <String>[];

  @override
  Future<DriveSession?> readLocalSession() async => local;
  @override
  Future<DriveSession> authorize({
    required Set<String> scopes,
    required String? expectedAccountId,
    required bool selectAccount,
  }) async {
    calls.add('authorize');
    return local = _grant(account: nextAccount);
  }

  @override
  Future<void> clearLocalSession() async {
    calls.add('clear');
    local = null;
  }

  @override
  Future<void> rememberFolder(DriveFolderBinding folder) async {
    calls.add('remember');
    local = _grant(account: folder.accountId);
  }

  @override
  Future<DriveSession> renew({required String accountId}) async {
    calls.add('renew');
    return local!;
  }
}

final class _Metadata implements DriveMetadataClient {
  List<DriveFileMetadata> files = [];
  DriveFileMetadata folder = _folder();
  DriveFileMetadata? known;
  Object? failure;
  String failAt = 'list';
  String? hookAt;
  Future<void> Function()? hook;
  Completer<void>? pending;
  final calls = <String>[];
  final accounts = <String>[];
  Future<void> _call(String operation, String accountId) async {
    calls.add(operation);
    accounts.add(accountId);
    if (operation == hookAt) await hook?.call();
    if (operation == failAt && failure != null) throw failure!;
  }

  @override
  Future<String> getMyDriveRootId({required String accountId}) async {
    await _call('root', accountId);
    await pending?.future;
    return 'actual-root';
  }

  @override
  Future<DriveFileMetadata> getFile({
    required String accountId,
    required String fileId,
  }) async {
    if (fileId == _binding(accountId).folderId) {
      await _call('folder', accountId);
      return folder;
    }
    await _call('copy', accountId);
    if (known == null) {
      throw const DriveMetadataFailure(DriveMetadataIssue.notFound);
    }
    return known!;
  }

  @override
  Future<List<DriveFileMetadata>> listFiles({
    required String accountId,
    String? parentId,
    String? name,
    String? mimeType,
    Map<String, String>? appProperties,
  }) async {
    expect(parentId, _binding(accountId).folderId);
    expect(name, isNull);
    expect(mimeType, isNull);
    expect(appProperties, driveAutofinanceCopyProperties);
    await _call('list', accountId);
    return files;
  }

  @override
  Future<DriveFileMetadata> createAutofinanceFolder({
    required String accountId,
  }) => throw StateError('No debe crear recursos');
}

final class _Credentials implements DriveMetadataCredentialSource {
  _Credentials(this.access);
  final DriveAccess access;
  @override
  Future<DriveMetadataCredential> readCredential({
    required String accountId,
  }) async => DriveMetadataCredential(
    session: access.snapshot.session!,
    accessToken: 'synthetic-token',
  );
}

Map<String, Object?> _json(DriveFileMetadata file) => {
  'id': file.id,
  'name': file.name,
  'mimeType': file.mimeType,
  'parents': file.parents,
  'trashed': file.trashed,
  'appProperties': file.appProperties,
  if (file.version != null) 'version': file.version,
  if (file.modifiedTime != null)
    'modifiedTime': file.modifiedTime!.toUtc().toIso8601String(),
};

void main() {
  late _Provider provider;
  late DriveAccessSession access;
  late _Metadata metadata;
  late DriveCopyLocator locator;
  late DateTime clock;
  setUp(() async {
    clock = _now;
    provider = _Provider();
    access = DriveAccessSession(provider: provider, now: () => clock);
    await access.restoreLocalSession();
    metadata = _Metadata();
    locator = DriveCopyLocator(access: access, metadata: metadata);
  });
  tearDown(() async {
    expect(
      provider.calls.where((c) => c == 'remember' || c == 'renew'),
      isEmpty,
    );
    await access.dispose();
  });

  test(
    'construir es pasivo y cero copias devuelve sin_copia asociado',
    () async {
      expect(metadata.calls, isEmpty);
      expect(provider.calls, isEmpty);
      final result = await locator.findCopy();
      expect(result.status, DriveCopyStatus.noCopy);
      expect(result.copy, isNull);
      expect(result.account!.permissionId, 'account-a');
      expect(result.folder!.folderId, 'folder-account-a');
      expect(metadata.calls, ['root', 'folder', 'list']);
      expect(provider.calls, isEmpty);
      expect(driveAutofinanceCopyName, 'autofinance.sqlite');
    },
  );
  test('una copia devuelve todos los metadatos actuales y cuenta', () async {
    metadata.files = [_copy()];
    final result = await locator.findCopy();
    expect(result.status, DriveCopyStatus.present);
    expect(result.copy!.id, 'copy-a');
    expect(result.copy!.name, 'autofinance.sqlite');
    expect(result.copy!.version, '42');
    expect(result.copy!.modifiedTime, _now);
    expect(result.account!.permissionId, 'account-a');
    expect(result.candidates, isEmpty);
  });
  for (final known in [false, true]) {
    test(
      'renombrado conserva identidad por marca, ID conocido=$known',
      () async {
        metadata.files = [_copy(name: 'Mi copia renombrada.sqlite')];
        metadata.known = metadata.files.single;
        final result = await locator.findCopy(
          knownCopy: known ? _known() : null,
        );
        expect(result.status, DriveCopyStatus.present);
        expect(result.copy!.name, 'Mi copia renombrada.sqlite');
      },
    );
    test('varias copias son ambiguas, ID conocido=$known', () async {
      metadata.files = [
        _copy(id: 'copy-b', name: 'otra.sqlite', version: '999'),
        _copy(),
      ];
      metadata.known = _copy();
      final result = await locator.findCopy(knownCopy: known ? _known() : null);
      expect(result.status, DriveCopyStatus.ambiguous);
      expect(result.copy, isNull);
      expect(result.candidates.map((c) => c.id), ['copy-a', 'copy-b']);
      expect(result.account!.permissionId, 'account-a');
      expect(() => result.candidates.clear(), throwsUnsupportedError);
    });
  }
  test('deduplica por ID y usa metadatos de la consulta posterior', () async {
    metadata.known = _copy(version: '41');
    metadata.files = [_copy(), _copy()];
    final result = await locator.findCopy(knownCopy: _known());
    expect(result.status, DriveCopyStatus.present);
    expect(result.copy!.version, '42');
  });
  test('ID conocido sigue presente si no aparece en lista', () async {
    metadata.known = _copy();
    expect(
      (await locator.findCopy(knownCopy: _known())).status,
      DriveCopyStatus.present,
    );
  });
  test(
    'papelera se ignora y nunca se interpreta como copia presente',
    () async {
      metadata.files = [_copy(trashed: true)];
      expect((await locator.findCopy()).status, DriveCopyStatus.noCopy);
      metadata.known = metadata.files.single;
      final result = await locator.findCopy(knownCopy: _known());
      expect(result.status, DriveCopyStatus.inaccessible);
      expect(result.metadataFailure!.issue, DriveMetadataIssue.notFound);
    },
  );
  for (final file in [
    _copy(parent: 'other-folder'),
    _copy(properties: {}),
    _copy(mimeType: driveFolderMimeType),
    _copy(mimeType: 'application/vnd.google-apps.shortcut'),
  ]) {
    for (final known in [false, true]) {
      test(
        'rechaza copia inválida ${file.mimeType}/${file.parents}, conocido=$known',
        () async {
          metadata.files = [file];
          metadata.known = file;
          final result = await locator.findCopy(
            knownCopy: known ? _known() : null,
          );
          expect(result.status, DriveCopyStatus.inaccessible);
          expect(result.copy, isNull);
          expect(
            result.issue,
            file.parents.single == 'other-folder'
                ? DriveCopyIssue.copyOutsideFolder
                : DriveCopyIssue.invalidCopy,
          );
        },
      );
    }
  }
  for (final file in [
    _copy(id: ''),
    _copy(name: ''),
    _copy(version: null),
    _copy(version: 'invalid'),
    _copy(modifiedTime: false),
  ]) {
    test(
      'metadatos incompletos nunca anuncian presente ni sin_copia ${file.id}/${file.name}/${file.version}/${file.modifiedTime}',
      () async {
        metadata.files = [file];
        final result = await locator.findCopy();
        expect(result.status, DriveCopyStatus.inaccessible);
        expect(
          result.metadataFailure!.issue,
          DriveMetadataIssue.incompleteResponse,
        );
      },
    );
  }
  for (final folder in [
    _folder(parent: 'elsewhere'),
    _folder(trashed: true),
    _folder(properties: {}),
    _folder(mimeType: 'application/octet-stream'),
  ]) {
    test(
      'carpeta inválida impide buscar archivos ${folder.parents}/${folder.trashed}/${folder.mimeType}/${folder.appProperties}',
      () async {
        metadata.folder = folder;
        final result = await locator.findCopy();
        expect(result.status, DriveCopyStatus.inaccessible);
        expect(result.issue, DriveCopyIssue.invalidFolder);
        expect(metadata.calls, ['root', 'folder']);
      },
    );
  }
  for (final phase in ['folder', 'copy']) {
    test('GET no puede devolver otro ID: $phase', () async {
      metadata.folder = phase == 'folder'
          ? _folder(id: 'unexpected')
          : _folder();
      metadata.known = _copy(id: 'unexpected');
      final result = await locator.findCopy(knownCopy: _known());
      expect(result.status, DriveCopyStatus.inaccessible);
      expect(
        result.metadataFailure!.issue,
        DriveMetadataIssue.incompleteResponse,
      );
    });
  }
  test(
    'sin ID conocido accesible no sustituye por otra copia marcada',
    () async {
      metadata.files = [_copy(id: 'copy-b')];
      final result = await locator.findCopy(knownCopy: _known());
      expect(result.status, DriveCopyStatus.inaccessible);
      expect(result.metadataFailure!.issue, DriveMetadataIssue.notFound);
      expect(metadata.calls, ['root', 'folder', 'copy']);
    },
  );
  for (final issue in DriveMetadataIssue.values) {
    test('fallo $issue conserva información y nunca es sin_copia', () async {
      metadata.failure = DriveMetadataFailure(
        issue,
        httpStatus: 429,
        retryAfter: const Duration(seconds: 10),
      );
      final result = await locator.findCopy();
      expect(result.status, DriveCopyStatus.inaccessible);
      expect(result.metadataFailure, same(metadata.failure));
      expect(result.account!.permissionId, 'account-a');
      expect(result.copy, isNull);
    });
  }
  test('excepción externa no filtra su mensaje', () async {
    metadata.failure = StateError('private-message');
    final result = await locator.findCopy();
    expect(result.status, DriveCopyStatus.inaccessible);
    expect(
      result.metadataFailure!.issue,
      DriveMetadataIssue.incompleteResponse,
    );
    expect(result.toString(), 'DriveCopyResult(inaccessible)');
  });
  test('sin carpeta seleccionada no hace red', () async {
    await access.disconnect();
    provider.local = _grant(folder: false);
    await access.restoreLocalSession();
    final result = await locator.findCopy();
    expect(result.issue, DriveCopyIssue.folderNotSelected);
    expect(metadata.calls, isEmpty);
  });
  test('desconexión y caducidad no autorizan ni renuevan', () async {
    clock = _now.add(const Duration(hours: 2));
    var result = await locator.findCopy();
    expect(result.status, DriveCopyStatus.inaccessible);
    expect(result.account!.permissionId, 'account-a');
    expect(result.accessIssue, DriveAccessIssue.credentialExpired);
    await access.disconnect();
    result = await locator.findCopy();
    expect(result.account, isNull);
    expect(result.status, DriveCopyStatus.inaccessible);
    expect(metadata.calls, isEmpty);
    expect(provider.calls, ['clear']);
  });
  for (final reference in [
    _known(account: 'account-b'),
    _known(folderId: 'other-folder'),
  ]) {
    test(
      'referencia de otra cuenta/carpeta no consulta ID ${reference.accountId}/${reference.folderId}',
      () async {
        final result = await locator.findCopy(knownCopy: reference);
        expect(result.accessIssue, DriveAccessIssue.accountChangeRequired);
        expect(metadata.calls, isEmpty);
      },
    );
  }
  for (final phase in ['root', 'folder', 'copy', 'list']) {
    test(
      'cambio de cuenta durante $phase descarta resultado anterior',
      () async {
        metadata.files = [_copy()];
        metadata.known = _copy();
        metadata.hookAt = phase;
        metadata.hook = () async {
          await access.changeAccount();
        };
        final result = await locator.findCopy(knownCopy: _known());
        expect(result.status, DriveCopyStatus.inaccessible);
        expect(result.accessIssue, DriveAccessIssue.accountChangeRequired);
        expect(result.account!.permissionId, 'account-a');
        expect(result.copy, isNull);
        expect(metadata.accounts.toSet(), {'account-a'});
        metadata.hookAt = null;
        metadata.folder = _folder(account: 'account-b');
        metadata.files = [_copy(id: 'copy-b', parent: 'folder-account-b')];
        final next = await locator.findCopy();
        expect(next.status, DriveCopyStatus.present);
        expect(next.account!.permissionId, 'account-b');
        expect(next.copy!.id, 'copy-b');
      },
    );
    test('caducidad durante $phase nunca anuncia copia', () async {
      metadata.known = _copy();
      metadata.files = [_copy()];
      metadata.hookAt = phase;
      metadata.hook = () async {
        clock = _now.add(const Duration(hours: 2));
      };
      final result = await locator.findCopy(knownCopy: _known());
      expect(result.status, DriveCopyStatus.inaccessible);
      expect(result.accessIssue, DriveAccessIssue.credentialExpired);
    });
  }
  test('consultas simultáneas fallan sin duplicar operaciones', () async {
    metadata.pending = Completer<void>();
    final first = locator.findCopy();
    await expectLater(
      locator.findCopy(),
      throwsA(
        isA<DriveAccessFailure>().having(
          (e) => e.issue,
          'issue',
          DriveAccessIssue.operationInProgress,
        ),
      ),
    );
    metadata.pending!.complete();
    expect((await first).status, DriveCopyStatus.noCopy);
    expect(metadata.calls, ['root', 'folder', 'list']);
  });

  test(
    'HTTP real: marca, carpeta, paginación y solo GET de metadatos',
    () async {
      final requests = <http.Request>[];
      var multiple = false;
      final client = MockClient((request) async {
        requests.add(request);
        expect(request.method, 'GET');
        expect(request.body, isEmpty);
        expect(request.url.queryParameters['alt'], isNull);
        expect(request.url.host, 'www.googleapis.com');
        final params = request.url.queryParameters;
        if (request.url.path.endsWith('/root')) {
          return http.Response(
            jsonEncode({'id': 'actual-root', 'mimeType': driveFolderMimeType}),
            200,
          );
        }
        if (request.url.path.endsWith('/folder-account-a')) {
          return http.Response(jsonEncode(_json(_folder())), 200);
        }
        if (request.url.path.endsWith('/copy-a')) {
          return http.Response(
            jsonEncode(_json(_copy(name: 'Renombrado.sqlite'))),
            200,
          );
        }
        expect(request.url.path, '/drive/v3/files');
        expect(
          params['q'],
          "trashed=false and 'folder-account-a' in parents and appProperties has { key='autofinanceRole' and value='databaseCopyV1' }",
        );
        expect(params['fields'], contains('version'));
        expect(params['fields'], contains('modifiedTime'));
        if (params['pageToken'] == null) {
          return http.Response(
            jsonEncode({'files': [], 'nextPageToken': 'page-2'}),
            200,
          );
        }
        expect(params['pageToken'], 'page-2');
        return http.Response(
          jsonEncode({
            'files': [
              _json(_copy(name: 'Renombrado.sqlite')),
              if (multiple) _json(_copy(id: 'copy-b')),
            ],
          }),
          200,
        );
      });
      addTearDown(client.close);
      final realLocator = DriveCopyLocator(
        access: access,
        metadata: HttpDriveMetadataClient(
          client: client,
          credentials: _Credentials(access),
          now: () => _now,
        ),
      );
      final single = await realLocator.findCopy(knownCopy: _known());
      expect(single.status, DriveCopyStatus.present);
      expect(single.copy!.name, 'Renombrado.sqlite');
      expect(single.copy!.version, '42');
      multiple = true;
      expect(
        (await realLocator.findCopy(knownCopy: _known())).status,
        DriveCopyStatus.ambiguous,
      );
      expect(requests.length, 10);
      expect(provider.calls, isEmpty);
    },
  );
  test('HTTP: homónimo ajeno y papelera no son candidatas', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/root')) {
        return http.Response(
          jsonEncode({'id': 'actual-root', 'mimeType': driveFolderMimeType}),
          200,
        );
      }
      if (request.url.path.endsWith('/folder-account-a')) {
        return http.Response(jsonEncode(_json(_folder())), 200);
      }
      expect(request.method, 'GET');
      // Simular los filtros del servidor sobre recursos ajenos y papelera.
      final files = [_copy(properties: {}), _copy(trashed: true)];
      final visible = files.where(
        (f) =>
            !f.trashed &&
            f.appProperties['autofinanceRole'] == 'databaseCopyV1',
      );
      return http.Response(
        jsonEncode({'files': visible.map(_json).toList()}),
        200,
      );
    });
    addTearDown(client.close);
    final realLocator = DriveCopyLocator(
      access: access,
      metadata: HttpDriveMetadataClient(
        client: client,
        credentials: _Credentials(access),
        now: () => _now,
      ),
    );
    expect((await realLocator.findCopy()).status, DriveCopyStatus.noCopy);
  });
}
