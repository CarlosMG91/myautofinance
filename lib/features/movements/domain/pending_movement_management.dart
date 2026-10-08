import '../../../core/persistence/unit_of_work.dart';
import 'movement_management.dart';
import 'movement_repository.dart';
import 'pending_movement_repository.dart';

/// Casos de bandeja, independientes de Flutter y de los lectores de importación.
final class PendingMovementManagement {
  PendingMovementManagement({
    required this._repository,
    required this._unitOfWork,
    this._errorMessage,
  });

  final PendingMovementRepository _repository;
  final UnitOfWork _unitOfWork;
  final MovementErrorMessage? _errorMessage;

  Future<PendingMovementPage> readPage({
    PendingMovementQuery? query,
    MovementCursor? after,
    int limit = 100,
  }) => _guard(
    () => _repository.readPendingPage(query: query, after: after, limit: limit),
  );

  /// Para un movimiento o un lote de UUID capturados; sin alcance por filtros.
  Future<void> assignCategory(
    PendingMovementSelection selection,
    String categoryId,
  ) => _guard(() {
    MovementSelection([categoryId]);
    return _unitOfWork.run(
      () => _repository.assignPendingCategory(selection, categoryId),
    );
  });

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on MovementFailure {
      rethrow;
    } catch (error) {
      throw MovementFailure(
        _errorMessage?.call(error) ?? 'No se pudo completar la operación de pendientes. Inténtalo de nuevo.',
      );
    }
  }
}
