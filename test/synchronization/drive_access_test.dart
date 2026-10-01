import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';

final _initialTime = DateTime.utc(2026, 10, 1, 10);

DriveSession _grant({
  String accountId = 'synthetic-account-a',
  String? email = 'a@example.invalid',
  DateTime? until,
  Set<String> scopes = const {driveFileScope},
  DriveFolderBinding? folder,
}) => DriveSession(
  account: DriveAccount(permissionId: accountId, emailAddress: email),
  validUntil: until ?? _initialTime.add(const Duration(hours: 1)),
  grantedScopes: scopes,
  folder: folder,
);

// Metadatos sintéticos, sin SDK, tokens, SQLite ni servicios del prototipo.
final class _FakeProvider implements DriveSessionProvider {
  DriveSession? local;
  DriveSession? nextGrant;
  Object? authorizeFailure;
  Object? renewFailure;
  bool failClear = false;
  bool failRemember = false;
  final calls = <String>[];
  Set<String>? requestedScopes;
  String? expectedAccountId;
  bool? selectAccount;
  Completer<DriveSession>? pendingAuthorization;

  @override
  Future<DriveSession?> readLocalSession() async {
    calls.add('readLocal');
    return local;
  }

  @override
  Future<DriveSession> authorize({
    required Set<String> scopes,
    required String? expectedAccountId,
    required bool selectAccount,
  }) async {
    calls.add('authorize');
    requestedScopes = scopes;
    this.expectedAccountId = expectedAccountId;
    this.selectAccount = selectAccount;
    if (authorizeFailure != null) throw authorizeFailure!;
    local = pendingAuthorization != null
        ? await pendingAuthorization!.future
        : nextGrant ?? _grant();
    return local!;
  }

  @override
  Future<DriveSession> renew({required String accountId}) async {
    calls.add('renew');
    expectedAccountId = accountId;
    if (renewFailure != null) {
      if (renewFailure case DriveAccessFailure(
        issue: DriveAccessIssue.credentialExpired,
      )) {
        local = _grant(until: _initialTime, folder: local?.folder);
      }
      throw renewFailure!;
    }
    local = nextGrant ?? _grant(folder: local?.folder);
    return local!;
  }

  @override
  Future<void> clearLocalSession() async {
    calls.add('clearLocal');
    if (failClear) throw StateError('synthetic-private-provider-detail');
    local = null;
  }

  @override
  Future<void> rememberFolder(DriveFolderBinding folder) async {
    calls.add('rememberFolder');
    if (failRemember) throw StateError('synthetic-private-provider-detail');
    if (local?.account.permissionId != folder.accountId) {
      throw const DriveAccessFailure(DriveAccessIssue.accountChangeRequired);
    }
    local = DriveSession(
      account: local!.account,
      validUntil: local!.validUntil,
      grantedScopes: local!.grantedScopes,
      folder: folder,
    );
  }
}

void main() {
  late _FakeProvider provider;
  late DriveAccess access;
  late DateTime now;

  setUp(() {
    provider = _FakeProvider();
    now = _initialTime;
    access = DriveAccessSession(provider: provider, now: () => now);
  });
  tearDown(() => access.dispose());

  test('Construcción y lectura pasiva no llaman al proveedor', () {
    expect(access.snapshot.status, DriveAccessStatus.disconnected);
    expect(access.snapshot.session, isNull);
    now = now.add(const Duration(days: 1));
    expect(access.snapshot.status, DriveAccessStatus.disconnected);
    expect(provider.calls, isEmpty);
  });

  test('Restauración sin sesión solo lee almacenamiento local', () async {
    expect(
      (await access.restoreLocalSession()).status,
      DriveAccessStatus.disconnected,
    );
    expect(provider.calls, ['readLocal']);
  });

  test('Restaura identidad, carpeta y permiso sin renovar', () async {
    final folder = DriveFolderBinding(
      accountId: 'synthetic-account-a',
      folderId: 'synthetic-folder-a',
    );
    provider.local = _grant(folder: folder);
    final result = await access.restoreLocalSession();
    expect(result.status, DriveAccessStatus.authorized);
    expect(result.account!.permissionId, folder.accountId);
    expect(result.session!.folder, same(folder));
    expect(provider.calls, ['readLocal']);
  });

  test('Solicitud expresa emite conectando y pide solo drive.file', () async {
    final states = <DriveAccessStatus>[];
    final subscription = access.changes.listen((s) => states.add(s.status));
    final result = await access.requestAccess();
    await Future<void>.delayed(Duration.zero);
    expect(result.status, DriveAccessStatus.authorized);
    expect(provider.calls, ['readLocal', 'authorize']);
    expect(provider.requestedScopes, {driveFileScope});
    expect(provider.expectedAccountId, isNull);
    expect(provider.selectAccount, isTrue);
    expect(states, [
      DriveAccessStatus.connecting,
      DriveAccessStatus.authorized,
    ]);
    await subscription.cancel();
  });

  test('Cancelación inicial conserva desconexión y no crea sesión', () async {
    provider.authorizeFailure = const DriveAccessFailure(
      DriveAccessIssue.cancelled,
    );
    final result = await access.requestAccess();
    expect(result.status, DriveAccessStatus.disconnected);
    expect(result.issue, DriveAccessIssue.cancelled);
    expect(provider.local, isNull);
  });

  test(
    'Cancelación conserva sesión local incluso sin restore previo',
    () async {
      provider.local = _grant();
      provider.authorizeFailure = const DriveAccessFailure(
        DriveAccessIssue.cancelled,
      );
      final result = await access.requestAccess();
      expect(result.status, DriveAccessStatus.authorized);
      expect(result.session, same(provider.local));
      expect(result.issue, DriveAccessIssue.cancelled);
      expect(provider.expectedAccountId, 'synthetic-account-a');
      expect(provider.selectAccount, isFalse);
    },
  );

  test(
    'Denegación se distingue de cancelación sin sesión utilizable',
    () async {
      provider.authorizeFailure = const DriveAccessFailure(
        DriveAccessIssue.permissionDenied,
      );
      final result = await access.requestAccess();
      expect(result.status, DriveAccessStatus.permissionDenied);
      expect(result.issue, DriveAccessIssue.permissionDenied);
      expect(result.session, isNull);
    },
  );

  test('Caducidad local en el límite no inicia renovación ni red', () async {
    provider.local = _grant();
    await access.restoreLocalSession();
    now = provider.local!.validUntil;
    expect(access.snapshot.status, DriveAccessStatus.credentialExpired);
    expect(access.snapshot.session, isNull);
    expect(access.snapshot.account!.permissionId, 'synthetic-account-a');
    expect(provider.calls, ['readLocal']);
  });

  test('Restaura credencial caducada sin conceder acceso', () async {
    provider.local = _grant(until: now);
    final result = await access.restoreLocalSession();
    expect(result.status, DriveAccessStatus.credentialExpired);
    expect(result.session, isNull);
    expect(provider.calls, ['readLocal']);
  });

  test('Renovación expresa conserva cuenta y carpeta, sin authorize', () async {
    final folder = DriveFolderBinding(
      accountId: 'synthetic-account-a',
      folderId: 'synthetic-folder-a',
    );
    provider.local = _grant(until: now, folder: folder);
    await access.restoreLocalSession();
    final result = await access.renewAccess();
    expect(result.status, DriveAccessStatus.authorized);
    expect(result.session!.folder, same(folder));
    expect(provider.expectedAccountId, 'synthetic-account-a');
    expect(provider.calls, ['readLocal', 'renew']);
  });

  test('Revocación/invalid_grant exige reautorización expresa', () async {
    await access.requestAccess();
    provider.renewFailure = const DriveAccessFailure(
      DriveAccessIssue.credentialExpired,
    );
    final result = await access.renewAccess();
    expect(result.status, DriveAccessStatus.credentialExpired);
    expect(result.session, isNull);
    expect(provider.calls.where((c) => c == 'authorize'), hasLength(1));
    expect(
      (await access.restoreLocalSession()).status,
      DriveAccessStatus.credentialExpired,
    );
    provider.authorizeFailure = null;
    expect((await access.requestAccess()).status, DriveAccessStatus.authorized);
    expect(provider.selectAccount, isFalse);
  });

  test('Renovación sin sesión no inicia proveedor', () async {
    expect(
      (await access.renewAccess()).status,
      DriveAccessStatus.credentialExpired,
    );
    expect(provider.calls, isEmpty);
  });

  test('Desconexión borra sesión/carpeta y es idempotente sin red', () async {
    await access.requestAccess();
    await access.rememberFolder(
      DriveFolderBinding(
        accountId: 'synthetic-account-a',
        folderId: 'synthetic-folder-a',
      ),
    );
    final result = await access.disconnect();
    expect(result.status, DriveAccessStatus.disconnected);
    expect(result.account, isNull);
    expect(result.session, isNull);
    expect(provider.local, isNull);
    await access.disconnect();
    expect(provider.calls.where((c) => c == 'clearLocal'), hasLength(2));
  });

  test('Cambio expreso limpia antes de seleccionar otra cuenta', () async {
    await access.requestAccess();
    await access.rememberFolder(
      DriveFolderBinding(
        accountId: 'synthetic-account-a',
        folderId: 'synthetic-folder-a',
      ),
    );
    provider.nextGrant = _grant(accountId: 'synthetic-account-b');
    final result = await access.changeAccount();
    expect(provider.calls.sublist(provider.calls.length - 2), [
      'clearLocal',
      'authorize',
    ]);
    expect(provider.selectAccount, isTrue);
    expect(provider.expectedAccountId, isNull);
    expect(result.account!.permissionId, 'synthetic-account-b');
    expect(result.session!.folder, isNull);
  });

  test(
    'Cancelar cambio de cuenta no recupera sesión ni carpeta antigua',
    () async {
      await access.requestAccess();
      provider.authorizeFailure = const DriveAccessFailure(
        DriveAccessIssue.cancelled,
      );
      final result = await access.changeAccount();
      expect(result.status, DriveAccessStatus.disconnected);
      expect(result.issue, DriveAccessIssue.cancelled);
      expect(result.account, isNull);
      expect(provider.local, isNull);
    },
  );

  for (final operation in ['request', 'renew', 'restore']) {
    test(
      'Rechaza cambio implícito durante $operation y elimina sesión',
      () async {
        await access.requestAccess();
        provider.nextGrant = _grant(accountId: 'synthetic-account-b');
        final result = switch (operation) {
          'request' => await access.requestAccess(),
          'renew' => await access.renewAccess(),
          _ => await (() async {
            provider.local = provider.nextGrant;
            return access.restoreLocalSession();
          })(),
        };
        expect(result.issue, DriveAccessIssue.accountChangeRequired);
        expect(result.session, isNull);
        expect(provider.local, isNull);
      },
    );
  }

  for (final scopes in <Set<String>>[
    {},
    {'https://www.googleapis.com/auth/drive'},
    {driveFileScope, 'openid'},
  ]) {
    test('Rechaza permisos insuficientes o ampliados: $scopes', () async {
      provider.nextGrant = _grant(scopes: scopes);
      final result = await access.requestAccess();
      expect(result.issue, DriveAccessIssue.invalidSession);
      expect(result.session, isNull);
      expect(provider.local, isNull);
    });
  }

  test('Rechaza sesión restaurada con carpeta de otra cuenta', () async {
    provider.local = _grant(
      folder: DriveFolderBinding(
        accountId: 'synthetic-account-b',
        folderId: 'synthetic-folder-b',
      ),
    );
    expect(
      (await access.restoreLocalSession()).issue,
      DriveAccessIssue.invalidSession,
    );
    expect(provider.local, isNull);
  });

  test(
    'Recordar carpeta solo persiste para cuenta activa y no consulta Drive',
    () async {
      await access.requestAccess();
      final folder = DriveFolderBinding(
        accountId: 'synthetic-account-a',
        folderId: 'synthetic-folder-a',
      );
      final result = await access.rememberFolder(folder);
      expect(result.session!.folder, same(folder));
      expect(provider.local!.folder, same(folder));
      final previousCalls = provider.calls.length;
      expect(
        (await access.rememberFolder(
          DriveFolderBinding(
            accountId: 'synthetic-account-b',
            folderId: 'synthetic-folder-b',
          ),
        )).issue,
        DriveAccessIssue.accountChangeRequired,
      );
      expect(provider.calls, hasLength(previousCalls));
      expect(provider.local!.folder, same(folder));
    },
  );

  test('Carpeta con acceso caducado no se persiste', () async {
    await access.requestAccess();
    now = provider.local!.validUntil;
    final result = await access.rememberFolder(
      DriveFolderBinding(
        accountId: 'synthetic-account-a',
        folderId: 'synthetic-folder-a',
      ),
    );
    expect(result.status, DriveAccessStatus.credentialExpired);
    expect(provider.calls, isNot(contains('rememberFolder')));
  });

  test(
    'Fallo de escritura de carpeta no modifica memoria ni sesión segura',
    () async {
      await access.requestAccess();
      provider.failRemember = true;
      final result = await access.rememberFolder(
        DriveFolderBinding(
          accountId: 'synthetic-account-a',
          folderId: 'synthetic-folder-a',
        ),
      );
      expect(result.status, DriveAccessStatus.error);
      expect(result.session, isNull);
      expect(provider.local!.folder, isNull);
    },
  );

  test(
    'Fallo de borrado no afirma desconexión y bloquea reutilización',
    () async {
      await access.requestAccess();
      provider.failClear = true;
      final result = await access.disconnect();
      expect(result.status, DriveAccessStatus.error);
      expect(result.issue, DriveAccessIssue.secureStorageFailure);
      expect(result.session, isNull);
      final previousCalls = provider.calls.length;
      for (final action in [
        access.requestAccess,
        access.changeAccount,
        access.restoreLocalSession,
        access.renewAccess,
      ]) {
        expect((await action()).issue, DriveAccessIssue.secureStorageFailure);
      }
      expect(provider.calls, hasLength(previousCalls));
      provider.failClear = false;
      expect(
        (await access.disconnect()).status,
        DriveAccessStatus.disconnected,
      );
      expect(provider.local, isNull);
    },
  );

  test('Cambio de cuenta con borrado fallido no abre autorización', () async {
    await access.requestAccess();
    provider.failClear = true;
    expect(
      (await access.changeAccount()).issue,
      DriveAccessIssue.secureStorageFailure,
    );
    expect(provider.calls.where((c) => c == 'authorize'), hasLength(1));
  });

  test('Errores externos y diagnósticos no exponen material privado', () async {
    final printed = <String>[];
    provider.authorizeFailure = StateError('synthetic-private-provider-detail');
    final result = await runZoned(
      access.requestAccess,
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => printed.add(line),
      ),
    );
    expect(result.status, DriveAccessStatus.error);
    expect(result.issue, DriveAccessIssue.unavailable);
    expect(printed, isEmpty);
    expect(result.toString(), isNot(contains('synthetic-private')));
    expect(_grant().toString(), 'DriveSession');
    expect(_grant().account.toString(), 'DriveAccount');
    expect(
      const DriveAccessFailure(DriveAccessIssue.unavailable).toString(),
      'DriveAccessFailure(unavailable)',
    );
  });

  test(
    'Operaciones concurrentes se rechazan sin corromper la sesión',
    () async {
      provider.pendingAuthorization = Completer<DriveSession>();
      final pending = access.requestAccess();
      await Future<void>.delayed(Duration.zero);
      expect(access.snapshot.status, DriveAccessStatus.connecting);
      for (final action in [
        access.disconnect,
        access.changeAccount,
        access.dispose,
      ]) {
        await expectLater(
          action(),
          throwsA(
            isA<DriveAccessFailure>().having(
              (e) => e.issue,
              'issue',
              DriveAccessIssue.operationInProgress,
            ),
          ),
        );
      }
      provider.pendingAuthorization!.complete(_grant());
      expect((await pending).status, DriveAccessStatus.authorized);
      expect(provider.calls, ['readLocal', 'authorize']);
    },
  );

  test('Instalaciones independientes no comparten sesión ni carpeta', () async {
    final secondProvider = _FakeProvider();
    final second = DriveAccessSession(provider: secondProvider, now: () => now);
    await access.requestAccess();
    await second.restoreLocalSession();
    expect(second.snapshot.status, DriveAccessStatus.disconnected);
    await second.requestAccess();
    await access.disconnect();
    expect(second.snapshot.status, DriveAccessStatus.authorized);
    expect(secondProvider.local, isNotNull);
    await second.dispose();
  });

  test('dispose solo cierra observadores y no borra la sesión', () async {
    await access.requestAccess();
    final previousCalls = provider.calls.length;
    await access.dispose();
    expect(provider.calls, hasLength(previousCalls));
    expect(provider.local, isNotNull);
    await expectLater(access.changes, emitsDone);
  });

  test('Identidad no depende de etiqueta y datos vacíos se rechazan', () {
    expect(_grant(email: null).account.permissionId, 'synthetic-account-a');
    final scopes = {driveFileScope};
    final grant = _grant(scopes: scopes);
    scopes.clear();
    expect(grant.grantedScopes, {driveFileScope});
    expect(() => grant.grantedScopes.clear(), throwsUnsupportedError);
    expect(
      () => DriveAccount(permissionId: ' '),
      throwsA(isA<DriveAccessFailure>()),
    );
    expect(
      () => DriveFolderBinding(accountId: 'a', folderId: ''),
      throwsA(isA<DriveAccessFailure>()),
    );
  });
}
