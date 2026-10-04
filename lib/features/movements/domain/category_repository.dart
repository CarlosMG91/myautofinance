/// Identidad estable; la condición de ingreso procede siempre de la raíz.
final class CategoryNode {
  const CategoryNode({
    required this.id,
    required this.parentId,
    required this.name,
    required this.isIncome,
    required this.archived,
    required this.depth,
  });
  final String id;
  final String? parentId;
  final String name;
  final bool isIncome;
  final bool archived;
  final int depth;
}

final class CategoryFailure implements Exception {
  const CategoryFailure(this.message, {this.budgetConflicts = const []});
  final String message;
  final List<CategoryBudgetConflict> budgetConflicts;
  @override
  String toString() => message;
}

/// Solapamiento en el árbol propuesto, incluidos meses y nodos archivados.
final class CategoryBudgetConflict {
  const CategoryBudgetConflict({
    required this.month,
    required this.ancestorId,
    required this.ancestorPath,
    required this.descendantId,
    required this.descendantPath,
  });

  /// Mes ISO YYYY-MM-01; no depende del periodo visible en pantalla.
  final String month;
  final String ancestorId;
  final String ancestorPath;
  final String descendantId;
  final String descendantPath;
}

abstract interface class CategoryRepository {
  Future<List<CategoryNode>> list({bool includeArchived = true});
  Future<CategoryNode?> get(String id);

  /// Incluye referencias históricas y archivadas de toda la rama.
  Future<bool> hasReferences(String id);
  Future<CategoryNode> create({
    required String name,
    String? parentId,
    bool? isIncome,
  });

  /// Edición completa: en descendientes isIncome debe ser null.
  /// Al promover, null conserva el tipo heredado; un tipo distinto se rechaza.
  /// El traslado conserva referencias y valida todos los meses presupuestados.
  Future<CategoryNode> edit(
    String id, {
    required String name,
    required String? parentId,
    required bool? isIncome,
  });
  Future<void> setArchived(String id, {required bool archived});
}
