import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  const max = 9223372036854775807;
  final month = Month(2026, 1);
  WealthValue value(
    String id,
    int cents, {
    Liquidity? liquidity,
    AccountKind kind = AccountKind.account,
  }) => WealthValue(
    id: id,
    account: AccountRecord(
      id: id,
      name: id,
      kind: kind,
      activeFrom: month,
      activeThrough: null,
      liquidity: liquidity,
    ),
    amountCents: cents,
  );
  WealthReading read(List<WealthValue> values) => WealthReading.fromSnapshot(
    WealthSnapshot(
      month: month,
      snapshotId: 'photo',
      status: WealthSnapshotStatus.complete,
      values: values,
      pending: [],
    ),
  );
  for (final liquidity in Liquidity.values) {
    test('Overflow de activos ${liquidity.name} se rechaza', () {
      expect(
        () => read([
          value('a', max, liquidity: liquidity),
          value('b', 1, liquidity: liquidity),
        ]),
        throwsA(isA<WealthFailure>()),
      );
    });
  }
  test('Overflow de deudas se rechaza', () {
    expect(
      () => read([
        value('a', max, kind: AccountKind.debt),
        value('b', 1, kind: AccountKind.debt),
      ]),
      throwsA(isA<WealthFailure>()),
    );
  });
  test('Agregados comprobados y neto exacto con cancelación intermedia', () {
    final result = read([
      value('a', max, liquidity: Liquidity.liquid),
      value('b', 1, liquidity: Liquidity.medium),
      value('d', 1, kind: AccountKind.debt),
    ]);
    expect(result.liquidAssetsCents, max);
    expect(() => result.totals!.assetsCents, throwsA(isA<WealthFailure>()));
    expect(result.totals!.netWorthCents, max);
    final overflow = read([
      value('a', max, liquidity: Liquidity.liquid),
      value('b', 1, liquidity: Liquidity.medium),
    ]);
    expect(() => overflow.totals!.netWorthCents, throwsA(isA<WealthFailure>()));
  });
}
