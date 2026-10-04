import '../../../core/persistence/unit_of_work.dart';
import 'movement_repository.dart';

/// Distingue conservar un campo opcional de retirarlo explícitamente con null.
final class MovementChange<T> {
  const MovementChange(this.value);
  final T value;
}

/// Convierte EUR sin miles a céntimos exactos, sin redondear ni usar double.
int parseMovementAmount(String text) {
  final match = RegExp(r'^([+-]?)([0-9]+)(?:[.,]([0-9]{1,2}))?$')
      .firstMatch(text.trim());
  if (match == null) {
    throw const MovementFailure(
      'Usa coma o punto y hasta dos decimales, sin separadores de miles.',
    );
  }
  var cents =
      BigInt.parse(match[2]!) * BigInt.from(100) +
      BigInt.parse((match[3] ?? '').padRight(2, '0'));
  if (match[1] == '-') cents = -cents;
  if (cents == BigInt.zero ||
      cents < BigInt.parse('-9223372036854775808') ||
      cents > BigInt.parse('9223372036854775807')) {
    throw const MovementFailure(
      'El importe debe ser distinto de cero y caber en int64.',
    );
  }
  return cents.toInt();
}

String? normalizeMovementDiscretion(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

typedef MovementErrorMessage = String? Function(Object error);

/// Casos individuales para ambas plataformas. Repositorio y UnitOfWork deben
/// compartir conexión. La cuenta y categoría se revalidan en la persistencia.
final class MovementManagement {
  MovementManagement({
    required this._repository,
    required this._unitOfWork,
    this._errorMessage,
  });

  final MovementRepository _repository;
  final UnitOfWork _unitOfWork;
  final MovementErrorMessage? _errorMessage;

  Future<MovementRecord> get(String id) => _guard(() => _require(id));

  Future<MovementRecord> create({
    required String accountId,
    required String valueDate,
    required String concept,
    required String amount,
    String? categoryId,
    String? discretion,
  }) => _guard(
    () => _unitOfWork.run(() async {
      _validateId(accountId);
      if (categoryId != null) _validateId(categoryId);
      _validateConcept(concept);
      return _repository.create(
        MovementInput(
          accountId: accountId,
          valueDate: ValueDate.parse(valueDate),
          concept: concept,
          amountCents: parseMovementAmount(amount),
          categoryId: categoryId,
          discretion: normalizeMovementDiscretion(discretion),
        ),
      );
    }),
  );

  /// Solo los argumentos suministrados cambian. category/discretion ausentes
  /// conservan su valor; MovementChange(null) significa retirada explícita.
  Future<MovementRecord> edit(
    String id, {
    String? accountId,
    String? valueDate,
    String? concept,
    String? amount,
    MovementChange<String?>? category,
    MovementChange<String?>? discretion,
  }) => _guard(
    () => _unitOfWork.run(() async {
      final old = await _require(id);
      final data = MovementInput(
        accountId: accountId ?? old.data.accountId,
        valueDate: valueDate == null
            ? old.data.valueDate
            : ValueDate.parse(valueDate),
        concept: concept ?? old.data.concept,
        amountCents: amount == null
            ? old.data.amountCents
            : parseMovementAmount(amount),
        categoryId: category == null ? old.data.categoryId : category.value,
        discretion: discretion == null
            ? old.data.discretion
            : normalizeMovementDiscretion(discretion.value),
      );
      _validateId(data.accountId);
      if (data.categoryId != null) _validateId(data.categoryId!);
      _validateConcept(data.concept);
      if (data.accountId != old.data.accountId ||
          data.valueDate.value != old.data.valueDate.value ||
          data.concept != old.data.concept ||
          data.amountCents != old.data.amountCents ||
          data.categoryId != old.data.categoryId) {
        await _repository.edit(id, data);
      }
      if (data.discretion != old.data.discretion) {
        await _repository.setDiscretion(id, data.discretion);
      }
      return _require(id);
    }),
  );

  Future<MovementRecord> setDiscretion(String id, String? value) =>
      edit(id, discretion: MovementChange(value));

  /// Invocar después de la confirmación de borrado en la interfaz.
  Future<void> delete(String id) => _guard(
    () => _unitOfWork.run(() async {
      _validateId(id);
      await _repository.delete(id);
    }),
  );

  Future<MovementRecord> _require(String id) async {
    _validateId(id);
    return await _repository.get(id) ??
        (throw const MovementFailure('El movimiento no existe.'));
  }

  void _validateId(String id) {
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    ).hasMatch(id)) {
      throw const MovementFailure('Identificador inválido.');
    }
  }

  void _validateConcept(String concept) {
    if (concept.trim().isEmpty) {
      throw const MovementFailure('El concepto es obligatorio.');
    }
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on MovementFailure {
      rethrow;
    } catch (error) {
      throw MovementFailure(
        _errorMessage?.call(error) ?? 'No se pudo completar la operación de movimientos. Inténtalo de nuevo.',
      );
    }
  }
}
