import 'account_repository.dart';
import 'wealth_repository.dart';

/// Magnitudes en céntimos de una única foto completa del día 1.
final class WealthTotals {
  const WealthTotals._({
    required this.liquidAssetsCents,
    required this.mediumAssetsCents,
    required this.illiquidAssetsCents,
    required this.debtsCents,
  });

  final int liquidAssetsCents;
  final int mediumAssetsCents;
  final int illiquidAssetsCents;
  final int debtsCents;

  int get assetsCents => _checked(
    BigInt.from(liquidAssetsCents) +
        BigInt.from(mediumAssetsCents) +
        BigInt.from(illiquidAssetsCents),
  );
  int get netWorthCents => _checked(
    BigInt.from(liquidAssetsCents) +
        BigInt.from(mediumAssetsCents) +
        BigInt.from(illiquidAssetsCents) -
        BigInt.from(debtsCents),
  );
}

/// Conserva valores y pendientes del repositorio, sin completar ni arrastrar.
/// [totals] null significa «sin dato», nunca cero ni una suma parcial.
final class WealthReading {
  const WealthReading._(this.snapshot, this.totals);

  factory WealthReading.fromSnapshot(WealthSnapshot snapshot) {
    if (snapshot.status != WealthSnapshotStatus.complete) {
      return WealthReading._(snapshot, null);
    }
    var liquid = BigInt.zero, medium = BigInt.zero;
    var illiquid = BigInt.zero, debts = BigInt.zero;
    for (final value in snapshot.values) {
      final amount = BigInt.from(value.amountCents);
      if (value.account.kind == AccountKind.debt) {
        debts += amount;
      } else {
        switch (value.account.liquidity) {
          case Liquidity.liquid:
            liquid += amount;
          case Liquidity.medium:
            medium += amount;
          case Liquidity.illiquid:
            illiquid += amount;
          case null:
            throw const WealthFailure(
              'Falta la clasificación de liquidez del activo en el mes.',
            );
        }
      }
    }
    return WealthReading._(
      snapshot,
      WealthTotals._(
        liquidAssetsCents: _checked(liquid),
        mediumAssetsCents: _checked(medium),
        illiquidAssetsCents: _checked(illiquid),
        debtsCents: _checked(debts),
      ),
    );
  }

  final WealthSnapshot snapshot;
  final WealthTotals? totals;
  Month get month => snapshot.month;
  WealthSnapshotStatus get status => snapshot.status;
  List<WealthValue> get values => snapshot.values;
  List<AccountRecord> get pending => snapshot.pending;

  /// Numerador disponible para futuros indicadores; no descuenta deudas.
  /// También exige foto completa, aunque ya estén registrados los líquidos.
  int? get liquidAssetsCents => totals?.liquidAssetsCents;
}

int _checked(BigInt value) {
  if (value < BigInt.from(-9223372036854775808) ||
      value > BigInt.from(9223372036854775807)) {
    throw const WealthFailure('Una cifra patrimonial excede el rango int64.');
  }
  return value.toInt();
}
