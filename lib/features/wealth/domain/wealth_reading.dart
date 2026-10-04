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

  int get assetsCents =>
      liquidAssetsCents + mediumAssetsCents + illiquidAssetsCents;
  int get netWorthCents => assetsCents - debtsCents;
}

/// Conserva valores y pendientes del repositorio, sin completar ni arrastrar.
/// [totals] null significa «sin dato», nunca cero ni una suma parcial.
final class WealthReading {
  const WealthReading._(this.snapshot, this.totals);

  factory WealthReading.fromSnapshot(WealthSnapshot snapshot) {
    if (snapshot.status != WealthSnapshotStatus.complete) {
      return WealthReading._(snapshot, null);
    }
    var liquid = 0, medium = 0, illiquid = 0, debts = 0;
    for (final value in snapshot.values) {
      if (value.account.kind == AccountKind.debt) {
        debts += value.amountCents;
      } else {
        switch (value.account.liquidity) {
          case Liquidity.liquid:
            liquid += value.amountCents;
          case Liquidity.medium:
            medium += value.amountCents;
          case Liquidity.illiquid:
            illiquid += value.amountCents;
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
        liquidAssetsCents: liquid,
        mediumAssetsCents: medium,
        illiquidAssetsCents: illiquid,
        debtsCents: debts,
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
