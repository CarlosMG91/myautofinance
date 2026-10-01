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
  const CategoryFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class CategoryRepository {
  Future<List<CategoryNode>> list({bool includeArchived = true});
  Future<CategoryNode?> get(String id);
  Future<CategoryNode> create({
    required String name,
    String? parentId,
    bool? isIncome,
  });

  /// Edición completa: en descendientes isIncome debe ser null.
  Future<CategoryNode> edit(
    String id, {
    required String name,
    required String? parentId,
    required bool? isIncome,
  });
  Future<void> setArchived(String id, {required bool archived});
}
