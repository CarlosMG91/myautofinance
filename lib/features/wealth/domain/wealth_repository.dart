import 'account_repository.dart';

enum WealthSnapshotStatus { absent, incomplete, complete }

final class WealthValue {
  const WealthValue({
    required this.id,
    required this.account,
    required this.amountCents,
  });
  final String id;
  final AccountRecord account;
  final int amountCents;
}

/// Consulta independiente del mes. Las valoraciones parciales no son totales.
final class WealthSnapshot {
  WealthSnapshot({
    required this.month,
    required this.snapshotId,
    required this.status,
    required List<WealthValue> values,
    required List<AccountRecord> pending,
  }) : values = List.unmodifiable(values),
       pending = List.unmodifiable(pending);
  final Month month;
  final String? snapshotId;
  final WealthSnapshotStatus status;
  final List<WealthValue> values;
  final List<AccountRecord> pending;
}

final class WealthFailure implements Exception {
  const WealthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class WealthRepository {
  /// Crea una cabecera en preparación; no completa fichas ni copia otro mes.
  Future<void> prepare(Month month);

  /// Alta o corrección en el mismo mes, conservando identidad si ya existe.
  Future<void> setValue(Month month, String accountId, int amountCents);
  Future<void> deleteValue(Month month, String accountId);
  Future<void> deleteSnapshot(Month month);
  Future<WealthSnapshot> read(Month month);
}
