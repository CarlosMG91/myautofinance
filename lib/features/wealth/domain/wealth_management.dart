import '../../../core/persistence/unit_of_work.dart';
import 'account_repository.dart';
import 'wealth_repository.dart';
import 'wealth_reading.dart';

final class AccountDetails {
  AccountDetails({
    required this.account,
    required List<LiquidityPeriod> history,
  }) : history = List.unmodifiable(history);
  final AccountRecord account;
  final List<LiquidityPeriod> history;
}

/// Puertos de EP-004 inyectados; no mantiene una copia de la persistencia.
final class WealthManagement {
  WealthManagement({
    required this.accounts,
    required this.photos,
    required this._unitOfWork,
  });

  final AccountRepository accounts;
  final WealthRepository photos;
  final UnitOfWork _unitOfWork;

  Future<List<AccountRecord>> catalog() => accounts.list();

  /// Confirma la escritura y devuelve el historial en la misma transacción.
  Future<AccountDetails> changeLiquidity(
    String id,
    Month from,
    Liquidity liquidity,
  ) => _unitOfWork.run(() async {
    await accounts.changeLiquidity(id, from, liquidity);
    return details(id);
  });

  Future<AccountDetails> correctHistoricalLiquidity(
    String id,
    Month from,
    Month? until,
    Liquidity liquidity,
  ) => _unitOfWork.run(() async {
    await accounts.correctHistoricalLiquidity(id, from, until, liquidity);
    return details(id);
  });

  Future<WealthReading> readMonth(Month month) async =>
      WealthReading.fromSnapshot(await photos.read(month));

  /// Doce lecturas independientes; el patrimonio no tiene total anual.
  Future<List<WealthReading>> readYear(int year) async => List.unmodifiable(
    (await photos.readYear(year)).map(WealthReading.fromSnapshot),
  );

  Future<AccountDetails> create({
    required String name,
    required AccountKind kind,
    required Month activeFrom,
    Month? activeThrough,
    Liquidity? liquidity,
  }) => _unitOfWork.run(() async {
    final account = await accounts.create(
      name: name.trim(),
      kind: kind,
      activeFrom: activeFrom,
      activeThrough: activeThrough,
      liquidity: liquidity,
    );
    return details(account.id);
  });

  /// Nombre y baja se confirman juntos; un rechazo conserva toda la ficha.
  Future<AccountDetails> edit(
    String id, {
    required String name,
    required Month? activeThrough,
  }) => _unitOfWork.run(() async {
    final before = await details(id);
    if (before.account.activeThrough?.value != activeThrough?.value) {
      if (before.account.activeThrough != null || activeThrough == null) {
        throw const AccountFailure(
          'Una ficha cerrada conserva su mes de baja.',
        );
      }
      await accounts.close(id, activeThrough);
    }
    if (before.account.name != name.trim()) {
      await accounts.rename(id, name.trim());
    }
    return details(id);
  });

  /// Ficha e historial se leen en una misma transacción, también tras su baja.
  Future<AccountDetails> details(String id) => _unitOfWork.run(() async {
    final account = await accounts.get(id);
    if (account == null) throw const AccountFailure('La ficha no existe.');
    return AccountDetails(
      account: account,
      history: await accounts.history(id),
    );
  });
}
