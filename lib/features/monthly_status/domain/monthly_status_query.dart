import '../../../core/persistence/unit_of_work.dart';
import '../../budget/budget.dart';
import '../../movements/movements.dart';

enum MonthlyStatusFailureCode {
  persistence,
  overflow,
  invalidData,
  invalidated,
}

final class MonthlyStatusFailure implements Exception {
  const MonthlyStatusFailure(this.message, {required this.code});
  final String message;
  final MonthlyStatusFailureCode code;
  @override
  String toString() => message;
}

/// Cifras agregadas de una rama, Sin clasificar o total general.
/// La presencia presupuestaria se conserva aparte del importe aritmético.
final class MonthlyStatusTotals {
  const MonthlyStatusTotals({
    required this.plannedCents,
    required this.actualCents,
    required this.differenceCents,
    required this.budgetCount,
    required this.movementCount,
  });
  final int plannedCents, actualCents, differenceCents;
  final int budgetCount, movementCount;
  bool get hasBudget => budgetCount > 0;
  bool get hasMovements => movementCount > 0;
}

/// Nodo del árbol actual con origen propio y sumas de su rama.
/// ownBudget null significa ausencia; una partida de cero sigue presente.
final class MonthlyStatusRow {
  const MonthlyStatusRow({
    required this.category,
    required this.ownBudget,
    required this.actualDirectCents,
    required this.directMovementCount,
    required this.totals,
  });
  final CategoryDetails category;
  final BudgetRecord? ownBudget;
  final int actualDirectCents, directMovementCount;
  final MonthlyStatusTotals totals;
  String get categoryId => category.node.id;
  bool get hasOwnBudget => ownBudget != null;
  bool get hasDirectMovements => directMovementCount > 0;
}

/// Snapshot inmutable de mes, árbol, identidad/revisión y generación local.
/// rows está en preorden nombre/UUID: raíces activas y nodos con datos junto
/// a sus antecesores, incluido histórico archivado. Sin clasificar queda fuera.
final class MonthlyStatus {
  MonthlyStatus({
    required this.month,
    required Iterable<CategoryDetails> tree,
    required Iterable<MonthlyStatusRow> rows,
    required this.unclassified,
    required this.total,
    required this.datasetState,
    required this.categoryGeneration,
  }) : tree = List.unmodifiable(tree),
       rows = List.unmodifiable(rows);

  final BudgetMonth month;
  final List<CategoryDetails> tree;
  final List<MonthlyStatusRow> rows;
  final MonthlyStatusTotals unclassified, total;
  final DatasetState datasetState;
  final int categoryGeneration;
}

/// Releer después de guardar/importar o recibir invalidación de catálogo/base.
/// No hay caché. Todos los puertos deben compartir una transacción de lectura;
/// tras restaurar, app recompone con la conexión nueva y la invalidación común.
final class MonthlyStatusQuery {
  MonthlyStatusQuery({
    required this._movements,
    required this._budgets,
    required this._categories,
    required this._unitOfWork,
  });

  final MonthlyMovementTotalsReader _movements;
  final BudgetRepository _budgets;
  final CategoryManagement _categories;
  final UnitOfWork _unitOfWork;
  CategoryReadInvalidation get invalidation => _categories.invalidation;

  Future<MonthlyStatus> read(BudgetMonth month) async {
    try {
      return await _unitOfWork.run(() async {
        final generation = invalidation.generation;
        // Esta primera lectura fija también el snapshot de la transacción.
        final state = await _unitOfWork.readState();
        final tree = await _categories.list();
        final budgets = await _budgets.list(month);
        final reals = await _movements.readMonthTotals(
          int.parse(month.value.substring(0, 4)),
          int.parse(month.value.substring(5, 7)),
        );
        if (generation != invalidation.generation) {
          throw const MonthlyStatusFailure(
            'Los datos han cambiado. Vuelve a consultar el mes.',
            code: MonthlyStatusFailureCode.invalidated,
          );
        }
        return _assemble(month, tree, budgets, reals, state, generation);
      });
    } on MonthlyStatusFailure {
      rethrow;
    } on MovementTotalsOverflow {
      throw const MonthlyStatusFailure(
        'Una cifra del estado del mes excede el rango int64.',
        code: MonthlyStatusFailureCode.overflow,
      );
    } catch (_) {
      throw const MonthlyStatusFailure(
        'No se pudo consultar el estado del mes. Inténtalo de nuevo.',
        code: MonthlyStatusFailureCode.persistence,
      );
    }
  }

  MonthlyStatus _assemble(
    BudgetMonth month,
    List<CategoryDetails> tree,
    List<BudgetRecord> budgets,
    List<MonthlyMovementTotal> reals,
    DatasetState state,
    int generation,
  ) {
    final categories = <String, CategoryDetails>{};
    final children = <String?, List<CategoryDetails>>{};
    final sums = <String, _Sums>{};
    for (final category in tree) {
      final id = category.node.id;
      if (categories.containsKey(id)) _invalid();
      categories[id] = category;
      sums[id] = _Sums();
      (children[category.node.parentId] ??= []).add(category);
    }
    // Valida todo el árbol, también ramas sin registros.
    List<String> ancestors(String start) {
      final ids = <String>[];
      String? id = start;
      while (id != null) {
        final category = categories[id];
        if (category == null || ids.contains(id) || ids.length == 3) _invalid();
        ids.add(id);
        id = category.node.parentId;
      }
      if (categories[start]!.node.depth != ids.length) _invalid();
      return ids;
    }

    final paths = {for (final id in categories.keys) id: ancestors(id)};
    final included = <String>{
      for (final c in tree)
        if (c.node.parentId == null && !c.node.archived) c.node.id,
    };
    final ownBudgets = <String, BudgetRecord>{};
    for (final budget in budgets) {
      final id = budget.data.categoryId;
      if (budget.data.month.value != month.value ||
          ownBudgets.containsKey(id) ||
          !paths.containsKey(id)) {
        _invalid();
      }
      ownBudgets[id] = budget;
      for (final ancestor in paths[id]!) {
        included.add(ancestor);
        sums[ancestor]!.planned += BigInt.from(budget.data.amountCents);
        sums[ancestor]!.budgets += BigInt.one;
      }
    }
    final direct = <String?, MonthlyMovementTotal>{};
    final unclassified = _Sums();
    for (final real in reals) {
      final id = real.categoryId;
      if (real.movementCount <= 0 || direct.containsKey(id)) _invalid();
      direct[id] = real;
      if (id == null) {
        unclassified.actual = BigInt.from(real.amountCents);
        unclassified.movements = BigInt.from(real.movementCount);
      } else {
        if (!paths.containsKey(id)) _invalid();
        for (final ancestor in paths[id]!) {
          included.add(ancestor);
          sums[ancestor]!.actual += BigInt.from(real.amountCents);
          sums[ancestor]!.movements += BigInt.from(real.movementCount);
        }
      }
    }
    for (final siblings in children.values) {
      siblings.sort((a, b) {
        final name = a.node.name.compareTo(b.node.name);
        return name == 0 ? a.node.id.compareTo(b.node.id) : name;
      });
    }
    final rows = <MonthlyStatusRow>[];
    void visit(String? parentId) {
      for (final c in children[parentId] ?? <CategoryDetails>[]) {
        final id = c.node.id;
        if (included.contains(id)) {
          rows.add(
            MonthlyStatusRow(
              category: c,
              ownBudget: ownBudgets[id],
              actualDirectCents: direct[id]?.amountCents ?? 0,
              directMovementCount: direct[id]?.movementCount ?? 0,
              totals: sums[id]!.finish(),
            ),
          );
        }
        visit(id);
      }
    }

    visit(null);
    final total = _Sums()..add(unclassified);
    for (final root in children[null] ?? <CategoryDetails>[]) {
      total.add(sums[root.node.id]!);
    }
    return MonthlyStatus(
      month: month,
      tree: tree,
      rows: rows,
      unclassified: unclassified.finish(),
      total: total.finish(),
      datasetState: state,
      categoryGeneration: generation,
    );
  }
}

Never _invalid() => throw const MonthlyStatusFailure(
  'Los datos del mes o el árbol de categorías no son coherentes.',
  code: MonthlyStatusFailureCode.invalidData,
);

final class _Sums {
  BigInt planned = BigInt.zero, actual = BigInt.zero;
  BigInt budgets = BigInt.zero, movements = BigInt.zero;
  void add(_Sums other) {
    planned += other.planned;
    actual += other.actual;
    budgets += other.budgets;
    movements += other.movements;
  }

  MonthlyStatusTotals finish() => MonthlyStatusTotals(
    plannedCents: _checked(planned),
    actualCents: _checked(actual),
    differenceCents: _checked(actual - planned),
    budgetCount: _checked(budgets),
    movementCount: _checked(movements),
  );
  static final _min = BigInt.parse('-9223372036854775808');
  static final _max = BigInt.parse('9223372036854775807');
  static int _checked(BigInt amount) {
    if (amount < _min || amount > _max) {
      throw const MonthlyStatusFailure(
        'Una cifra del estado del mes excede el rango int64.',
        code: MonthlyStatusFailureCode.overflow,
      );
    }
    return amount.toInt();
  }
}
