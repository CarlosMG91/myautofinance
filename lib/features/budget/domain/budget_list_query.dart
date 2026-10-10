import '../../../core/persistence/unit_of_work.dart';
import '../../movements/movements.dart';
import 'budget_repository.dart';

final class BudgetListQuery {
  BudgetListQuery({
    required this.month,
    this.categoryId,
    this.unclassified = false,
    this.scope = MovementCategoryScope.branch,
  }) {
    if (unclassified && categoryId != null) {
      throw const BudgetFailure('Categoría ambigua.');
    }
    if (categoryId != null) MovementSelection([categoryId!]);
  }
  final BudgetMonth month;
  final String? categoryId;
  final bool unclassified;
  final MovementCategoryScope scope;
}

final class BudgetListEntry {
  const BudgetListEntry(this.record, this.category);
  final BudgetRecord record;
  final CategoryDetails category;
}

/// Lista de partidas originales, sin materializar ausencias o repartir padres.
final class BudgetListReader {
  BudgetListReader({
    required this._budgets,
    required this._categories,
    required this._unitOfWork,
  });
  final BudgetRepository _budgets;
  final CategoryManagement _categories;
  final UnitOfWork _unitOfWork;
  CategoryReadInvalidation get invalidation => _categories.invalidation;

  Future<List<BudgetListEntry>> read(BudgetListQuery query) async {
    final generation = invalidation.generation;
    try {
      final result = await _unitOfWork.run(() async {
        final nodes = {for (final c in await _categories.list()) c.node.id: c};
        if (query.categoryId != null && !nodes.containsKey(query.categoryId)) {
          throw const BudgetFailure(
            'La categoría no existe.',
            code: BudgetFailureCode.categoryNotFound,
          );
        }
        final records = await _budgets.list(query.month);
        bool includes(String id) {
          if (query.unclassified) return false;
          if (query.categoryId == null || id == query.categoryId) return true;
          if (query.scope == MovementCategoryScope.direct) return false;
          String? current = id;
          final seen = <String>{};
          while (current != null) {
            if (!seen.add(current) || !nodes.containsKey(current)) {
              throw const BudgetFailure('Árbol de categorías inválido.');
            }
            if (current == query.categoryId) return true;
            current = nodes[current]!.node.parentId;
          }
          return false;
        }

        final entries = <BudgetListEntry>[];
        for (final record in records) {
          final category = nodes[record.data.categoryId];
          if (category == null ||
              record.data.month.value != query.month.value) {
            throw const BudgetFailure('Partida de presupuesto inválida.');
          }
          if (includes(category.node.id)) {
            entries.add(BudgetListEntry(record, category));
          }
        }
        entries.sort((a, b) {
          final path = a.category.path.compareTo(b.category.path);
          return path == 0 ? a.record.id.compareTo(b.record.id) : path;
        });
        return List<BudgetListEntry>.unmodifiable(entries);
      });
      if (generation != invalidation.generation) {
        throw const BudgetFailure(
          'El árbol ha cambiado. Vuelve a consultar las partidas.',
        );
      }
      return result;
    } on BudgetFailure {
      rethrow;
    } catch (_) {
      throw const BudgetFailure(
        'No se pudieron consultar las partidas. Inténtalo de nuevo.',
      );
    }
  }
}
