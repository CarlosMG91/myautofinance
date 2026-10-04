import '../../../core/persistence/unit_of_work.dart';
import 'category_repository.dart';

/// Datos para gestión y selectores. El tipo efectivo procede de la raíz actual.
final class CategoryDetails {
  const CategoryDetails({required this.node, required this.path});
  final CategoryNode node;
  final String path;
}

/// Errores junto al campo correspondiente, sin perder el borrador del formulario.
final class CategoryFormFailure implements Exception {
  CategoryFormFailure(Map<String, String> fields)
    : fields = Map.unmodifiable(fields);
  final Map<String, String> fields;
  @override
  String toString() => fields.values.join(' ');
}

typedef CategoryErrorMessage = String? Function(Object error);

/// Casos de uso compartidos por Windows y Android; no conoce widgets ni SQLite.
/// El repositorio y la unidad de trabajo deben compartir la misma conexión.
final class CategoryManagement {
  CategoryManagement({
    required this._repository,
    required this._unitOfWork,
    this._errorMessage,
  });

  final CategoryRepository _repository;
  final UnitOfWork _unitOfWork;
  final CategoryErrorMessage? _errorMessage;

  /// Gestión e informes conservan las categorías archivadas.
  Future<List<CategoryDetails>> list() => _guard(() async {
    final nodes = await _repository.list();
    return List.unmodifiable(nodes.map((node) => _details(node, nodes)));
  });

  /// Solo para nuevas asignaciones. La persistencia vuelve a validar el estado
  /// al guardar un movimiento o una partida, aunque este selector haya caducado.
  Future<List<CategoryDetails>> assignmentOptions() => _guard(() async {
    final nodes = await _repository.list();
    return List.unmodifiable(
      nodes
          .where((node) => !node.archived)
          .map((node) => _details(node, nodes)),
    );
  });

  Future<CategoryDetails> get(String id) => _guard(() async {
    final nodes = await _repository.list();
    return _details(_find(id, nodes), nodes);
  });

  Future<bool> canChangeRootType(String id) => _guard(() async {
    final node = await _repository.get(id);
    if (node == null) throw const CategoryFailure('La categoría no existe.');
    return node.parentId == null && !await _repository.hasReferences(id);
  });

  Future<CategoryDetails> create({
    required String name,
    String? parentId,
    bool? isIncome,
  }) => _mutate(() async {
    _validateForm(name, parentId, isIncome);
    final node = await _repository.create(
      name: name.trim(),
      parentId: parentId,
      isIncome: isIncome,
    );
    return _details(node, await _repository.list());
  });

  /// Edición completa del formulario. null al promover conserva el tipo heredado.
  Future<CategoryDetails> edit(
    String id, {
    required String name,
    required String? parentId,
    required bool? isIncome,
  }) => _mutate(() async {
    final old = await _repository.get(id);
    if (old == null) throw const CategoryFailure('La categoría no existe.');
    _validateForm(
      name,
      parentId,
      isIncome,
      requiresRootType: old.parentId == null && parentId == null,
    );
    final node = await _repository.edit(
      id,
      name: name.trim(),
      parentId: parentId,
      isIncome: isIncome,
    );
    return _details(node, await _repository.list());
  });

  Future<CategoryDetails> rename(String id, {required String name}) =>
      _mutate(() async {
        final old = await _repository.get(id);
        if (old == null) throw const CategoryFailure('La categoría no existe.');
        _validateForm(name, old.parentId, null);
        final node = await _repository.edit(
          id,
          name: name.trim(),
          parentId: old.parentId,
          isIncome: old.parentId == null ? old.isIncome : null,
        );
        return _details(node, await _repository.list());
      });

  /// Traslado y promoción devuelven la nueva ruta y tipo sin tocar importes.
  Future<CategoryDetails> move(String id, {required String? parentId}) =>
      _mutate(() async {
        final old = await _repository.get(id);
        if (old == null) throw const CategoryFailure('La categoría no existe.');
        _validateForm(old.name, parentId, null);
        final node = await _repository.edit(
          id,
          name: old.name,
          parentId: parentId,
          isIncome: parentId == null ? old.isIncome : null,
        );
        return _details(node, await _repository.list());
      });

  Future<CategoryDetails> archive(String id) => _setArchived(id, true);
  Future<CategoryDetails> reactivate(String id) => _setArchived(id, false);

  Future<CategoryDetails> _setArchived(String id, bool archived) =>
      _mutate(() async {
        await _repository.setArchived(id, archived: archived);
        final nodes = await _repository.list();
        return _details(_find(id, nodes), nodes);
      });

  Future<T> _mutate<T>(Future<T> Function() action) =>
      _guard(() => _unitOfWork.run(action));

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on CategoryFailure {
      rethrow; // Conserva los meses, UUID y rutas de los conflictos.
    } on CategoryFormFailure {
      rethrow;
    } catch (error) {
      throw CategoryFailure(
        _errorMessage?.call(error) ?? 'No se pudo completar la operación de categorías. Inténtalo de nuevo.',
      );
    }
  }

  void _validateForm(
    String name,
    String? parentId,
    bool? isIncome, {
    bool requiresRootType = false,
  }) {
    final errors = <String, String>{};
    if (name.trim().isEmpty) errors['name'] = 'El nombre no puede estar vacío.';
    if (parentId != null && parentId.trim().isEmpty) {
      errors['parentId'] = 'Selecciona un padre válido o convierte en raíz.';
    }
    if (parentId != null && isIncome != null) {
      errors['isIncome'] =
          'El tipo se hereda de la raíz; no se edita en un hijo.';
    }
    if (requiresRootType && isIncome == null) {
      errors['isIncome'] = 'Selecciona Ingreso o Salida para la raíz.';
    }
    if (errors.isNotEmpty) throw CategoryFormFailure(errors);
  }

  CategoryNode _find(String id, List<CategoryNode> nodes) => nodes.firstWhere(
    (node) => node.id == id,
    orElse: () => throw const CategoryFailure('La categoría no existe.'),
  );

  CategoryDetails _details(CategoryNode node, List<CategoryNode> nodes) {
    final byId = {for (final item in nodes) item.id: item};
    final names = <String>[];
    final seen = <String>{};
    CategoryNode? current = node;
    while (current != null) {
      if (!seen.add(current.id)) {
        throw const CategoryFailure('La rama contiene un ciclo.');
      }
      names.add(current.name);
      final parent = current.parentId;
      current = parent == null
          ? null
          : byId[parent] ??
                (throw const CategoryFailure('El padre no existe.'));
    }
    return CategoryDetails(node: node, path: names.reversed.join(' / '));
  }
}
