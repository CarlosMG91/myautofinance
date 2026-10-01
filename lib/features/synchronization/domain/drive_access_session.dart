import 'dart:async';

import 'drive_access.dart';

/// Coordina metadatos y estados; el proveedor conserva todas las credenciales.
/// Su construcción no restaura sesión, autoriza ni consulta Drive.
final class DriveAccessSession implements DriveAccess {
  DriveAccessSession({required this._provider, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DriveSessionProvider _provider;
  final DateTime Function() _now;
  final _changes = StreamController<DriveAccessSnapshot>.broadcast();
  DriveSession? _session;
  var _state = const DriveAccessSnapshot(
    status: DriveAccessStatus.disconnected,
  );
  bool _busy = false;
  bool _disposed = false;
  bool _disconnectRequired = false;

  @override
  DriveAccessSnapshot get snapshot {
    if (_state.status == DriveAccessStatus.authorized &&
        !_session!.validUntil.isAfter(_now())) {
      return _makeState(
        DriveAccessStatus.credentialExpired,
        DriveAccessIssue.credentialExpired,
      );
    }
    return _state;
  }

  @override
  Stream<DriveAccessSnapshot> get changes => _changes.stream;

  DriveAccessSnapshot _makeState(
    DriveAccessStatus status, [
    DriveAccessIssue? issue,
  ]) => DriveAccessSnapshot(
    status: status,
    account: _session?.account,
    session: status == DriveAccessStatus.authorized ? _session : null,
    issue: issue,
  );

  void _emit(DriveAccessSnapshot state) {
    _state = state;
    _changes.add(state);
  }

  Future<DriveAccessSnapshot> _run(Future<void> Function() action) async {
    if (_disposed || _busy) {
      throw const DriveAccessFailure(DriveAccessIssue.operationInProgress);
    }
    _busy = true;
    final previous = snapshot;
    try {
      if (_disconnectRequired) {
        throw const DriveAccessFailure(DriveAccessIssue.secureStorageFailure);
      }
      await action();
    } on DriveAccessFailure catch (failure) {
      final issue = failure.issue;
      if (issue == DriveAccessIssue.cancelled) {
        _emit(
          _makeState(
            previous.status == DriveAccessStatus.authorized &&
                    !_session!.validUntil.isAfter(_now())
                ? DriveAccessStatus.credentialExpired
                : previous.status,
            issue,
          ),
        );
      } else {
        _emit(
          _makeState(switch (issue) {
            DriveAccessIssue.permissionDenied =>
              DriveAccessStatus.permissionDenied,
            DriveAccessIssue.credentialExpired =>
              DriveAccessStatus.credentialExpired,
            _ => DriveAccessStatus.error,
          }, issue),
        );
      }
    } catch (_) {
      // Nunca registrar ni envolver el texto de una excepción externa.
      _emit(_makeState(DriveAccessStatus.error, DriveAccessIssue.unavailable));
    } finally {
      _busy = false;
    }
    return snapshot;
  }

  Future<void> _clear() async {
    _disconnectRequired = true;
    _session = null;
    try {
      await _provider.clearLocalSession();
      _disconnectRequired = false;
    } catch (_) {
      throw const DriveAccessFailure(DriveAccessIssue.secureStorageFailure);
    }
  }

  Future<void> _accept(DriveSession session, String? expectedAccountId) async {
    DriveAccessIssue? invalid;
    if (expectedAccountId != null &&
        session.account.permissionId != expectedAccountId) {
      invalid = DriveAccessIssue.accountChangeRequired;
    } else if (session.grantedScopes.length != 1 ||
        !session.grantedScopes.contains(driveFileScope) ||
        (session.folder != null &&
            session.folder!.accountId != session.account.permissionId)) {
      invalid = DriveAccessIssue.invalidSession;
    }
    if (invalid != null) {
      await _clear();
      throw DriveAccessFailure(invalid);
    }
    _session = session;
    final valid = session.validUntil.isAfter(_now());
    _emit(
      _makeState(
        valid
            ? DriveAccessStatus.authorized
            : DriveAccessStatus.credentialExpired,
        valid ? null : DriveAccessIssue.credentialExpired,
      ),
    );
  }

  @override
  Future<DriveAccessSnapshot> restoreLocalSession() => _run(() async {
    final session = await _provider.readLocalSession();
    if (session == null) {
      _session = null;
      _emit(_makeState(DriveAccessStatus.disconnected));
    } else {
      await _accept(session, _session?.account.permissionId);
    }
  });

  Future<void> _authorize({required bool selectAccount}) async {
    final expected = _session?.account.permissionId;
    final previous = snapshot;
    _emit(_makeState(DriveAccessStatus.connecting));
    try {
      await _accept(
        await _provider.authorize(
          scopes: const {driveFileScope},
          expectedAccountId: expected,
          selectAccount: selectAccount,
        ),
        expected,
      );
    } on DriveAccessFailure catch (failure) {
      if (failure.issue != DriveAccessIssue.cancelled) rethrow;
      _emit(
        _makeState(
          previous.status == DriveAccessStatus.authorized &&
                  !_session!.validUntil.isAfter(_now())
              ? DriveAccessStatus.credentialExpired
              : previous.status,
          DriveAccessIssue.cancelled,
        ),
      );
    }
  }

  @override
  Future<DriveAccessSnapshot> requestAccess() => _run(() async {
    // Restaura primero la identidad local para no cambiar de cuenta al volver
    // a abrir la app y pulsar el botón sin restauración previa del consumidor.
    if (_session == null) {
      final local = await _provider.readLocalSession();
      if (local != null) await _accept(local, null);
    }
    await _authorize(selectAccount: _session == null);
  });

  @override
  Future<DriveAccessSnapshot> changeAccount() => _run(() async {
    await _clear();
    _emit(_makeState(DriveAccessStatus.disconnected));
    await _authorize(selectAccount: true);
  });

  @override
  Future<DriveAccessSnapshot> renewAccess() => _run(() async {
    final accountId = _session?.account.permissionId;
    if (accountId == null) {
      throw const DriveAccessFailure(DriveAccessIssue.credentialExpired);
    }
    _emit(_makeState(DriveAccessStatus.connecting));
    await _accept(await _provider.renew(accountId: accountId), accountId);
  });

  @override
  Future<DriveAccessSnapshot> disconnect() {
    // Permite reintentar un borrado fallido; ningún otro método puede reutilizarlo.
    if (!_busy && !_disposed) _disconnectRequired = false;
    return _run(() async {
      await _clear();
      _emit(_makeState(DriveAccessStatus.disconnected));
    });
  }

  @override
  Future<DriveAccessSnapshot> rememberFolder(DriveFolderBinding folder) => _run(
    () async {
      final active = snapshot.session;
      if (active == null) {
        throw const DriveAccessFailure(DriveAccessIssue.credentialExpired);
      }
      if (folder.accountId != active.account.permissionId) {
        throw const DriveAccessFailure(DriveAccessIssue.accountChangeRequired);
      }
      await _provider.rememberFolder(folder);
      await _accept(
        DriveSession(
          account: active.account,
          validUntil: active.validUntil,
          grantedScopes: active.grantedScopes,
          folder: folder,
        ),
        active.account.permissionId,
      );
    },
  );

  @override
  Future<void> dispose() async {
    if (_busy) {
      throw const DriveAccessFailure(DriveAccessIssue.operationInProgress);
    }
    if (_disposed) return;
    _disposed = true;
    await _changes.close();
  }
}
