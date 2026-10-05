import '../../../core/persistence/unit_of_work.dart';
import '../../movements/movements.dart';
import 'budget_repository.dart';

/// Fila del árbol actual. El importe propio nunca incluye descendientes.
/// Una partida nula significa ausencia; una partida con cero está registrada.
final class MonthlyBudgetRow {
  const MonthlyBudgetRow({required this.category, required this.budget});

  final CategoryDetails category;
  final BudgetRecord? budget;
  String get categoryId => category.node.id;
  int? get ownAmountCents => budget?.data.amountCents;
}

/// Instantánea inmutable de un mes. El histórico contiene solo partidas de
/// nodos archivados, con su ruta y jerarquía actuales, sin crear filas vacías.
final class MonthlyBudget {
  MonthlyBudget({
    required this.month,
    required Iterable<MonthlyBudgetRow> activeTree,
    required Iterable<MonthlyBudgetRow> archivedBudgets,
    required this.categoryGeneration,
  }) : activeTree = List.unmodifiable(activeTree),
       archivedBudgets = List.unmodifiable(archivedBudgets);

  final BudgetMonth month;
  final List<MonthlyBudgetRow> activeTree, archivedBudgets;
  final int categoryGeneration;
}

/// Lectura sin caché para PC y Android. Inyectar repositorios y unidad de
/// trabajo sobre la misma conexión, e invalidación compartida con EP-008.
final class MonthlyBudgetQuery {
  MonthlyBudgetQuery({
    required this._budgets,
    required this._categories,
    required this._unitOfWork,
  });

  final BudgetRepository _budgets;
  final CategoryManagement _categories;
  final UnitOfWork _unitOfWork;

  /// El consumidor vuelve a consultar su mes tras un cambio del árbol o una
  /// restauración. Tras guardar una partida debe volver a consultar también.
  CategoryReadInvalidation get invalidation => _categories.invalidation;

  Future<MonthlyBudget> read(BudgetMonth month) async {
    try {
      return await _unitOfWork.run(() async {
        final categories = await _categories.list();
        final records = await _budgets.list(month);
        final byCategory = {
          for (final row in records) row.data.categoryId: row,
        };
        final children = <String?, List<CategoryDetails>>{};
        for (final category in categories) {
          (children[category.node.parentId] ??= []).add(category);
        }
        for (final siblings in children.values) {
          siblings.sort((a, b) {
            final name = a.node.name.compareTo(b.node.name);
            return name == 0 ? a.node.id.compareTo(b.node.id) : name;
          });
        }
        final active = <MonthlyBudgetRow>[];
        final archived = <MonthlyBudgetRow>[];
        void visit(String? parentId) {
          for (final category in children[parentId] ?? <CategoryDetails>[]) {
            final row = MonthlyBudgetRow(
              category: category,
              budget: byCategory[category.node.id],
            );
            if (!category.node.archived) {
              active.add(row);
            } else if (row.budget != null) {
              archived.add(row);
            }
            visit(category.node.id);
          }
        }

        visit(null);
        return MonthlyBudget(
          month: month,
          activeTree: active,
          archivedBudgets: archived,
          categoryGeneration: invalidation.generation,
        );
      });
    } on BudgetFailure {
      rethrow;
    } catch (_) {
      throw const BudgetFailure(
        'No se pudo consultar el presupuesto del mes. Inténtalo de nuevo.',
        code: BudgetFailureCode.persistence,
      );
    }
  }
}
