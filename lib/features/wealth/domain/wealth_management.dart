import '../../../core/persistence/unit_of_work.dart';
import 'account_repository.dart';
import 'wealth_repository.dart';

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
