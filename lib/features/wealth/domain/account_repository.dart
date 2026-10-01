/// Mes civil, sin conversión de zona horaria.
final class Month implements Comparable<Month> {
  Month(int year, int month)
    : value = '${'$year'.padLeft(4, '0')}-${'$month'.padLeft(2, '0')}-01' {
    if (year < 1 || year > 9999 || month < 1 || month > 12) {
      throw const AccountFailure('Mes fuera del calendario admitido.');
    }
  }
  factory Month.parse(String value) {
    if (!RegExp(r'^[0-9]{4}-[0-9]{2}-01$').hasMatch(value)) {
      throw const AccountFailure('El mes debe tener formato YYYY-MM-01.');
    }
    return Month(
      int.parse(value.substring(0, 4)),
      int.parse(value.substring(5, 7)),
    );
  }
  final String value;
  Month? get next {
    final year = int.parse(value.substring(0, 4));
    final month = int.parse(value.substring(5, 7));
    return year == 9999 && month == 12
        ? null
        : Month(month == 12 ? year + 1 : year, month == 12 ? 1 : month + 1);
  }

  @override
  int compareTo(Month other) => value.compareTo(other.value);
}

enum AccountKind { account, portfolio, debt }

enum Liquidity { liquid, medium, illiquid }

final class AccountRecord {
  const AccountRecord({
    required this.id,
    required this.name,
    required this.kind,
    required this.activeFrom,
    required this.activeThrough,
    this.liquidity,
  });
  final String id, name;
  final AccountKind kind;
  final Month activeFrom;
  final Month? activeThrough;

  /// Clasificación efectiva del mes consultado; null para deudas o get().
  final Liquidity? liquidity;
}

final class LiquidityPeriod {
  const LiquidityPeriod({
    required this.id,
    required this.from,
    required this.until,
    required this.liquidity,
  });
  final String id;
  final Month from;
  final Month? until;
  final Liquidity liquidity;
}

final class AccountFailure implements Exception {
  const AccountFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class AccountRepository {
  Future<AccountRecord> create({
    required String name,
    required AccountKind kind,
    required Month activeFrom,
    Month? activeThrough,
    Liquidity? liquidity,
  });
  Future<AccountRecord?> get(String id);
  Future<List<AccountRecord>> listForMonth(Month month);
  Future<List<LiquidityPeriod>> history(String id);
  Future<void> rename(String id, String name);

  /// Baja inclusiva; conserva identidad y referencias. No reutiliza una baja.
  Future<void> close(String id, Month activeThrough);

  /// Divide el periodo que contiene from; conserva cambios posteriores.
  Future<void> changeLiquidity(String id, Month from, Liquidity liquidity);

  /// Corrección explícita de [from, until); null alcanza el fin de vigencia.
  Future<void> correctHistoricalLiquidity(
    String id,
    Month from,
    Month? until,
    Liquidity liquidity,
  );
}
