import '../../../core/persistence/unit_of_work.dart';
import 'budget_repository.dart';

/// Operaciones mensuales para PC y Android. Repositorio y unidad de trabajo
/// deben compartir conexión; no guarda estado ni duplica persistencia.
final class BudgetManagement {
  BudgetManagement({required this._repository, required this._unitOfWork});

  final BudgetRepository _repository;
  final UnitOfWork _unitOfWork;

  Future<BudgetRecord> get(String id) => _guard(() => _require(id));

  Future<BudgetRecord> create({
    required BudgetMonth month,
    required String categoryId,
    required int amountCents,
  }) => _guard(
    () => _repository.create(
      BudgetInput(
        month: month,
        categoryId: categoryId,
        amountCents: amountCents,
      ),
    ),
  );

  /// Solo cambia los campos suministrados. Concepto, discrecionalidad y
  /// procedencia históricos se conservan exactamente, sin renormalizar signos.
  /// La lectura y escritura ocurren en la misma transacción.
  Future<BudgetRecord> edit(
    String id, {
    BudgetMonth? month,
    String? categoryId,
    int? amountCents,
  }) => _guard(
    () => _unitOfWork.run(() async {
      final old = await _require(id);
      final data = BudgetInput(
        month: month ?? old.data.month,
        categoryId: categoryId ?? old.data.categoryId,
        amountCents: amountCents ?? old.data.amountCents,
        concept: old.data.concept,
        discretion: old.data.discretion,
      );
      if (data.month.value == old.data.month.value &&
          data.categoryId == old.data.categoryId &&
          data.amountCents == old.data.amountCents) {
        return old;
      }
      return _repository.edit(id, data);
    }),
  );

  /// Invocar tras la confirmación explícita del consumidor. Cero se guarda
  /// como partida y nunca se interpreta como orden de borrado.
  Future<void> delete(String id) => _guard(() => _repository.delete(id));

  Future<BudgetRecord> _require(String id) async =>
      await _repository.get(id) ??
      (throw const BudgetFailure(
        'La partida no existe.',
        code: BudgetFailureCode.notFound,
      ));

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on BudgetFailure {
      rethrow;
    } catch (_) {
      throw const BudgetFailure(
        'No se pudo completar la operación de presupuesto. Inténtalo de nuevo.',
        code: BudgetFailureCode.persistence,
      );
    }
  }
}
