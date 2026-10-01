import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myautofinance/features/synchronization/data/drive_metadata_credential.dart';
import 'package:myautofinance/features/synchronization/data/http_drive_metadata_client.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';

final _now = DateTime.utc(2026, 10);

DriveSession _grant({
  String account = 'account-a',
  DriveFolderBinding? folder,
}) => DriveSession(
  account: DriveAccount(permissionId: account),
  validUntil: _now.add(const Duration(hours: 1)),
  grantedScopes: {driveFileScope},
  folder: folder,
);

DriveFileMetadata _folder({
  String id = 'folder-a',
  String name = 'Autofinance',
  String parent = 'actual-root',
  String mimeType = driveFolderMimeType,
  Map<String, String> properties = driveAutofinanceFolderProperties,
  bool trashed = false,
}) => DriveFileMetadata(
  id: id,
  name: name,
  mimeType: mimeType,
  parents: [parent],
  trashed: trashed,
  appProperties: properties,
);

final class _Provider implements DriveSessionProvider {
  DriveSession? local = _grant();
  bool failRemember = false;
  int writes = 0;
  final calls = <String>[];

  @override
  Future<DriveSession?> readLocalSession() async {
    calls.add('read');
    return local;
  }

  @override
  Future<DriveSession> authorize({
    required Set<String> scopes,
    required String? expectedAccountId,
    required bool selectAccount,
  }) async {
    calls.add('authorize');
    return local!;
  }

  @override
  Future<DriveSession> renew({required String accountId}) async {
    calls.add('renew');
    return local!;
  }

  @override
  Future<void> clearLocalSession() async {
    calls.add('clear');
    local = null;
  }

  @override
  Future<void> rememberFolder(DriveFolderBinding folder) async {
    calls.add('remember');
    if (failRemember) {
      throw const DriveAccessFailure(DriveAccessIssue.secureStorageFailure);
    }
    if (folder.accountId != local?.account.permissionId) {
      throw const DriveAccessFailure(DriveAccessIssue.accountChangeRequired);
    }
    writes++;
    local = _grant(account: folder.accountId, folder: folder);
  }
}

final class _Metadata implements DriveMetadataClient {
  final files = <String, DriveFileMetadata>{};
  final calls = <String>[];
  final accounts = <String>[];
  int creates = 0;
  int lists = 0;
  Object? getFailure;
  Object? listFailure;
  Object? createFailure;
  bool commitBeforeFailure = false;
  Completer<String>? pendingRoot;
  Future<void> Function()? afterList;
  List<DriveFileMetadata>? listOverride;
  DriveFileMetadata? createdOverride;
  bool duplicateOnCreate = false;

  @override
  Future<String> getMyDriveRootId({required String accountId}) async {
    calls.add('root');
    accounts.add(accountId);
    return pendingRoot == null ? 'actual-root' : pendingRoot!.future;
  }

  @override
  Future<DriveFileMetadata> getFile({
    required String accountId,
    required String fileId,
  }) async {
    calls.add('get');
    accounts.add(accountId);
    if (getFailure != null) throw getFailure!;
    final file = files[fileId];
    if (file == null || file.trashed) {
      throw const DriveMetadataFailure(DriveMetadataIssue.notFound);
    }
    return file;
  }

  @override
  Future<List<DriveFileMetadata>> listFiles({
    required String accountId,
    String? parentId,
    String? name,
    String? mimeType,
    Map<String, String>? appProperties,
  }) async {
    calls.add('list');
    accounts.add(accountId);
    lists++;
    expect(parentId, isNull);
    expect(name, isNull);
    expect(mimeType, isNull);
    expect(appProperties, driveAutofinanceFolderProperties);
    if (listFailure != null) throw listFailure!;
    await afterList?.call();
    final result =
        listOverride ??
        files.values
            .where(
              (file) =>
                  !file.trashed &&
                  appProperties!.entries.every(
                    (e) => file.appProperties[e.key] == e.value,
                  ),
            )
            .toList();
    return result;
  }

  @override
  Future<DriveFileMetadata> createAutofinanceFolder({
    required String accountId,
  }) async {
    calls.add('create');
    accounts.add(accountId);
    creates++;
    final file = createdOverride ?? _folder();
    if (createFailure == null || commitBeforeFailure) files[file.id] = file;
    if (createFailure != null) throw createFailure!;
    if (duplicateOnCreate) files['folder-b'] = _folder(id: 'folder-b');
    return file;
  }
}

Matcher _metadataIssue(DriveMetadataIssue issue) =>
    isA<DriveMetadataFailure>().having((f) => f.issue, 'issue', issue);
Matcher _accessIssue(DriveAccessIssue issue) =>
    isA<DriveAccessFailure>().having((f) => f.issue, 'issue', issue);

final class _Credentials implements DriveMetadataCredentialSource {
  _Credentials(this.access);
  final DriveAccess access;
  @override
  Future<DriveMetadataCredential> readCredential({
    required String accountId,
  }) async => DriveMetadataCredential(
    session: access.snapshot.session!,
    accessToken: 'synthetic-access',
  );
}

void main() {
  late _Provider provider;
  late _Metadata metadata;
  late DriveAccess access;
  late DriveFolderLocator locator;
  late DateTime now;

  setUp(() async {
    now = _now;
    provider = _Provider();
    metadata = _Metadata();
    access = DriveAccessSession(provider: provider, now: () => now);
    await access.restoreLocalSession();
    provider.calls.clear();
    locator = DriveFolderLocator(access: access, metadata: metadata);
  });
  tearDown(() => access.dispose());

  Future<void> remember(String id) async {
    await access.rememberFolder(
      DriveFolderBinding(accountId: 'account-a', folderId: id),
    );
    provider.calls.clear();
    provider.writes = 0;
  }

  test('construcción pasiva y consulta sin carpeta nunca crean', () async {
    expect(metadata.calls, isEmpty);
    expect(provider.calls, isEmpty);
    final result = await locator.findFolder();
    expect(result.status, DriveFolderStatus.notFound);
    expect(result.folder, isNull);
    expect(metadata.calls, ['root', 'list']);
    expect(metadata.creates, 0);
    expect(provider.calls, isEmpty);
  });

  test(
    'primera acción crea una carpeta y repetir reutiliza ID local',
    () async {
      final created = await locator.requestFolder();
      expect(created.status, DriveFolderStatus.created);
      expect(created.folder!.id, 'folder-a');
      expect(provider.local!.folder!.accountId, 'account-a');
      expect(provider.local!.folder!.folderId, 'folder-a');
      expect(provider.writes, 1);
      expect((await locator.requestFolder()).status, DriveFolderStatus.found);
      expect((await locator.findFolder()).status, DriveFolderStatus.found);
      expect(metadata.creates, 1);
      expect(provider.writes, 1);
      expect(metadata.accounts.toSet(), {'account-a'});
      expect(provider.calls, ['remember']);
    },
  );

  test(
    'otra instalación de la misma cuenta descubre marca y persiste su ID',
    () async {
      await locator.requestFolder();
      final androidProvider = _Provider();
      final androidAccess = DriveAccessSession(
        provider: androidProvider,
        now: () => now,
      );
      try {
        await androidAccess.restoreLocalSession();
        final android = DriveFolderLocator(
          access: androidAccess,
          metadata: metadata,
        );
        expect((await android.requestFolder()).folder!.id, 'folder-a');
        expect(androidProvider.local!.folder!.folderId, 'folder-a');
        expect(metadata.creates, 1);
        // La referencia sobrevive a reconstruir el servicio de la instalación.
        final restarted = DriveFolderLocator(
          access: androidAccess,
          metadata: metadata,
        );
        expect(
          (await restarted.requestFolder()).status,
          DriveFolderStatus.found,
        );
      } finally {
        await androidAccess.dispose();
      }
    },
  );

  test(
    'restaurar almacenamiento reutiliza el ID tras reconstruir sesión',
    () async {
      await locator.requestFolder();
      await access.dispose();
      access = DriveAccessSession(provider: provider, now: () => now);
      await access.restoreLocalSession();
      locator = DriveFolderLocator(access: access, metadata: metadata);
      expect((await locator.requestFolder()).folder!.id, 'folder-a');
      expect(metadata.creates, 1);
    },
  );

  for (final withBinding in [false, true]) {
    test(
      'renombrada conserva identidad con ID recordado=$withBinding',
      () async {
        metadata.files['folder-a'] = _folder(name: 'Mis copias renombradas');
        if (withBinding) await remember('folder-a');
        final result = await locator.requestFolder();
        expect(result.status, DriveFolderStatus.found);
        expect(result.folder!.name, 'Mis copias renombradas');
        expect(metadata.creates, 0);
      },
    );
  }

  test('carpeta ajena con mismo nombre no se adopta ni se altera', () async {
    final other = _folder(id: 'other', properties: {});
    metadata.files[other.id] = other;
    expect((await locator.requestFolder()).status, DriveFolderStatus.created);
    expect(metadata.files['other'], same(other));
    expect(metadata.files, hasLength(2));
  });

  test(
    'ID verificado sigue válido si el índice por marca aún está vacío',
    () async {
      metadata.files['folder-a'] = _folder();
      await remember('folder-a');
      metadata.listOverride = [];
      expect((await locator.requestFolder()).status, DriveFolderStatus.found);
      expect(metadata.creates, 0);
    },
  );

  for (final withBinding in [false, true]) {
    test(
      'varias candidatas bloquean selección y creación, ID recordado=$withBinding',
      () async {
        metadata.files['folder-a'] = _folder();
        metadata.files['folder-b'] = _folder(
          id: 'folder-b',
          name: 'Otra copia',
        );
        if (withBinding) await remember('folder-a');
        final result = await locator.requestFolder();
        expect(result.status, DriveFolderStatus.ambiguous);
        expect(result.candidateIds, ['folder-a', 'folder-b']);
        expect(result.folder, isNull);
        expect(() => result.candidateIds.clear(), throwsUnsupportedError);
        expect(metadata.creates, 0);
        expect(provider.writes, 0);
        expect(metadata.files, hasLength(2));
        expect(result.toString(), 'DriveFolderResult(ambiguous)');
      },
    );
  }

  test('candidata en root y otra movida también son ambiguas', () async {
    metadata.files['folder-a'] = _folder();
    metadata.files['folder-b'] = _folder(
      id: 'folder-b',
      parent: 'another-parent',
    );
    expect((await locator.requestFolder()).status, DriveFolderStatus.ambiguous);
    expect(metadata.creates, 0);
  });

  test('misma ID repetida entre páginas no inventa ambigüedad', () async {
    metadata.listOverride = [_folder(), _folder()];
    expect((await locator.findFolder()).status, DriveFolderStatus.found);
  });

  for (final trashed in [false, true]) {
    test(
      'ID borrado/inaccesible o papelera=$trashed no se sustituye',
      () async {
        if (trashed) metadata.files['folder-a'] = _folder(trashed: true);
        await remember('folder-a');
        metadata.files['folder-b'] = _folder(id: 'folder-b');
        final result = await locator.requestFolder();
        expect(result.status, DriveFolderStatus.missingOrInaccessible);
        expect(metadata.creates, 0);
        expect(provider.writes, 0);
        expect(provider.local!.folder!.folderId, 'folder-a');
      },
    );
  }

  for (final withBinding in [false, true]) {
    test(
      'carpeta movida bloquea creación con ID recordado=$withBinding',
      () async {
        metadata.files['folder-a'] = _folder(parent: 'nested-parent');
        if (withBinding) await remember('folder-a');
        expect((await locator.requestFolder()).status, DriveFolderStatus.moved);
        expect(metadata.creates, 0);
        expect(provider.writes, 0);
      },
    );
    test(
      'marca con tipo incorrecto bloquea creación con ID recordado=$withBinding',
      () async {
        metadata.files['folder-a'] = _folder(
          mimeType: 'application/octet-stream',
        );
        if (withBinding) await remember('folder-a');
        expect(
          (await locator.requestFolder()).status,
          DriveFolderStatus.invalidIdentity,
        );
        expect(metadata.creates, 0);
        expect(provider.writes, 0);
      },
    );
  }

  test('ID recordado sin marca ya no acredita identidad', () async {
    metadata.files['folder-a'] = _folder(properties: {});
    await remember('folder-a');
    expect(
      (await locator.requestFolder()).status,
      DriveFolderStatus.invalidIdentity,
    );
    expect(metadata.creates, 0);
    expect(provider.writes, 0);
  });

  test('GET responde con otra ID: no se guarda ni crea', () async {
    metadata.files['folder-a'] = _folder(id: 'wrong');
    await remember('folder-a');
    await expectLater(
      locator.requestFolder(),
      throwsA(_metadataIssue(DriveMetadataIssue.incompleteResponse)),
    );
    expect(metadata.creates, 0);
    expect(provider.writes, 0);
  });

  for (final issue in DriveMetadataIssue.values) {
    test(
      'fallo de descubrimiento ${issue.name} no equivale a ausencia',
      () async {
        final failure = DriveMetadataFailure(
          issue,
          httpStatus: 429,
          retryAfter: const Duration(seconds: 10),
        );
        metadata.listFailure = failure;
        await expectLater(locator.requestFolder(), throwsA(same(failure)));
        expect(metadata.creates, 0);
        expect(provider.writes, 0);
      },
    );
  }

  test('403 en ID recordado conserva referencia y no crea', () async {
    await remember('folder-a');
    metadata.getFailure = const DriveMetadataFailure(
      DriveMetadataIssue.permissionDenied,
      httpStatus: 403,
    );
    await expectLater(
      locator.requestFolder(),
      throwsA(_metadataIssue(DriveMetadataIssue.permissionDenied)),
    );
    expect(metadata.creates, 0);
    expect(provider.writes, 0);
  });

  test('fallo de almacenamiento no anuncia éxito; otro intento descubre carpeta creada', () async {
    provider.failRemember = true;
    await expectLater(
      locator.requestFolder(),
      throwsA(_accessIssue(DriveAccessIssue.secureStorageFailure)),
    );
    expect(provider.local!.folder, isNull);
    expect(metadata.creates, 1);
    provider.failRemember = false;
    await access.restoreLocalSession();
    expect((await locator.requestFolder()).status, DriveFolderStatus.found);
    expect(metadata.creates, 1);
    expect(provider.local!.folder!.folderId, 'folder-a');
  });

  for (final committed in [false, true]) {
    test(
      'POST sin confirmación con creación remota=$committed no repite a ciegas',
      () async {
        metadata.createFailure = const DriveMetadataFailure(
          DriveMetadataIssue.requestTimeout,
        );
        metadata.commitBeforeFailure = committed;
        await expectLater(
          locator.requestFolder(),
          throwsA(_metadataIssue(DriveMetadataIssue.requestTimeout)),
        );
        metadata.createFailure = null;
        final retry = await locator.requestFolder();
        expect(
          retry.status,
          committed
              ? DriveFolderStatus.found
              : DriveFolderStatus.creationUnconfirmed,
        );
        expect(metadata.creates, 1);
        if (!committed) {
          metadata.files['folder-a'] = _folder();
          expect(
            (await locator.requestFolder()).status,
            DriveFolderStatus.found,
          );
          expect(metadata.creates, 1);
        }
      },
    );
  }

  test('duplicado entre descubrir y crear produce ambigüedad sin guardar ni borrar', () async {
    metadata.duplicateOnCreate = true;
    final result = await locator.requestFolder();
    expect(result.status, DriveFolderStatus.ambiguous);
    expect(result.candidateIds, ['folder-a', 'folder-b']);
    expect(provider.writes, 0);
    expect(metadata.files, hasLength(2));
    expect((await locator.requestFolder()).status, DriveFolderStatus.ambiguous);
    expect(metadata.creates, 1);
  });

  test(
    'POST con ubicación incorrecta no guarda ni anuncia creación válida',
    () async {
      metadata.createdOverride = _folder(parent: 'not-root');
      await expectLater(
        locator.requestFolder(),
        throwsA(_metadataIssue(DriveMetadataIssue.incompleteResponse)),
      );
      expect(provider.writes, 0);
      expect((await locator.requestFolder()).status, DriveFolderStatus.moved);
      expect(metadata.creates, 1);
    },
  );

  test(
    'metadatos cambian de ubicación antes de guardar: no se persiste',
    () async {
      metadata.afterList = () async {
        if (metadata.lists == 2) {
          metadata.files['folder-a'] = _folder(parent: 'not-root');
        }
      };
      // El segundo listado proporciona la situación actual después del POST.
      expect((await locator.requestFolder()).status, DriveFolderStatus.moved);
      expect(provider.writes, 0);
      expect(metadata.creates, 1);
    },
  );

  test('sesión caducada o desconectada no hace red ni autoriza', () async {
    now = now.add(const Duration(hours: 2));
    await expectLater(
      locator.requestFolder(),
      throwsA(_accessIssue(DriveAccessIssue.credentialExpired)),
    );
    expect(metadata.calls, isEmpty);
    expect(provider.calls, isEmpty);
    now = _now;
    await access.disconnect();
    metadata.calls.clear();
    provider.calls.clear();
    await expectLater(
      locator.findFolder(),
      throwsA(_accessIssue(DriveAccessIssue.credentialExpired)),
    );
    expect(metadata.calls, isEmpty);
    expect(provider.calls, isEmpty);
  });

  test('caducidad durante descubrimiento impide POST', () async {
    metadata.afterList = () async {
      now = now.add(const Duration(hours: 2));
    };
    await expectLater(
      locator.requestFolder(),
      throwsA(_accessIssue(DriveAccessIssue.credentialExpired)),
    );
    expect(metadata.creates, 0);
    expect(provider.writes, 0);
  });

  test(
    'cambio de cuenta durante descubrimiento impide POST y referencia cruzada',
    () async {
      metadata.afterList = () async {
        await access.disconnect();
        provider.local = _grant(account: 'account-b');
        await access.restoreLocalSession();
      };
      await expectLater(
        locator.requestFolder(),
        throwsA(_accessIssue(DriveAccessIssue.accountChangeRequired)),
      );
      expect(metadata.creates, 0);
      expect(provider.writes, 0);
      expect(provider.local!.folder, isNull);
    },
  );

  test('dos peticiones locales simultáneas no crean dos carpetas', () async {
    metadata.pendingRoot = Completer<String>();
    final first = locator.requestFolder();
    await expectLater(
      locator.requestFolder(),
      throwsA(_accessIssue(DriveAccessIssue.operationInProgress)),
    );
    metadata.pendingRoot!.complete('actual-root');
    expect((await first).status, DriveFolderStatus.created);
    expect(metadata.creates, 1);
  });

  test('excepción externa saneada y bloqueo liberado tras fallo', () async {
    metadata.listFailure = StateError('private-details');
    await expectLater(
      locator.requestFolder(),
      throwsA(_metadataIssue(DriveMetadataIssue.incompleteResponse)),
    );
    metadata.listFailure = null;
    expect((await locator.findFolder()).status, DriveFolderStatus.notFound);
  });

  test('lista incoherente no permite adoptar una carpeta ajena', () async {
    metadata.listOverride = [_folder(properties: {})];
    await expectLater(
      locator.requestFolder(),
      throwsA(_metadataIssue(DriveMetadataIssue.incompleteResponse)),
    );
    expect(provider.writes, 0);
    expect(metadata.creates, 0);
  });

  test(
    'rechazo expreso del POST permite otro intento manual tras descubrir',
    () async {
      metadata.createFailure = const DriveMetadataFailure(
        DriveMetadataIssue.rateLimited,
        httpStatus: 429,
      );
      await expectLater(
        locator.requestFolder(),
        throwsA(_metadataIssue(DriveMetadataIssue.rateLimited)),
      );
      metadata.createFailure = null;
      expect((await locator.requestFolder()).status, DriveFolderStatus.created);
      expect(metadata.creates, 2);
      expect(provider.writes, 1);
    },
  );

  test('recorrido HTTP v3: raíz real, POST marcado y reutilización desde otra instalación', () async {
    final remote = <String, Map<String, dynamic>>{};
    final requests = <http.Request>[];
    final transport = MockClient((request) async {
      requests.add(request);
      expect(request.headers['Authorization'], 'Bearer synthetic-access');
      expect(request.followRedirects, isFalse);
      expect(request.url.queryParameters, isNot(contains('alt')));
      Object response;
      if (request.url.path == '/drive/v3/files/root') {
        response = {'id': 'actual-root', 'mimeType': driveFolderMimeType};
      } else if (request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body, {
          'name': 'Autofinance',
          'mimeType': driveFolderMimeType,
          'parents': ['root'],
          'appProperties': driveAutofinanceFolderProperties,
        });
        remote['remote-folder'] = {
          ...body,
          'id': 'remote-folder',
          'parents': ['actual-root'],
          'trashed': false,
        };
        response = remote['remote-folder']!;
      } else if (request.url.path == '/drive/v3/files') {
        expect(
          request.url.queryParameters['q'],
          "trashed=false and appProperties has { key='autofinanceRole' and value='backupFolderV1' }",
        );
        response = {'files': remote.values.toList()};
      } else {
        response = remote[request.url.pathSegments.last]!;
      }
      return http.Response(
        jsonEncode(response),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    try {
      final client = HttpDriveMetadataClient(
        client: transport,
        credentials: _Credentials(access),
        now: () => now,
      );
      locator = DriveFolderLocator(access: access, metadata: client);
      expect((await locator.requestFolder()).status, DriveFolderStatus.created);
      remote['remote-folder']!['name'] = 'Copias renombradas';
      expect(
        (await locator.requestFolder()).folder!.name,
        'Copias renombradas',
      );
      final secondProvider = _Provider();
      final secondAccess = DriveAccessSession(
        provider: secondProvider,
        now: () => now,
      );
      try {
        await secondAccess.restoreLocalSession();
        final secondClient = HttpDriveMetadataClient(
          client: transport,
          credentials: _Credentials(secondAccess),
          now: () => now,
        );
        final second = DriveFolderLocator(
          access: secondAccess,
          metadata: secondClient,
        );
        expect((await second.requestFolder()).status, DriveFolderStatus.found);
        expect(secondProvider.local!.folder!.folderId, 'remote-folder');
      } finally {
        await secondAccess.dispose();
      }
      expect(requests.where((r) => r.method == 'POST'), hasLength(1));
      expect(requests.every((r) => {'GET', 'POST'}.contains(r.method)), isTrue);
    } finally {
      transport.close();
    }
  });
}
