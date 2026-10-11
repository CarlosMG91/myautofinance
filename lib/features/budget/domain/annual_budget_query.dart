import '../../../core/persistence/unit_of_work.dart';
import '../../movements/movements.dart';
import 'budget_repository.dart';

enum AnnualBudgetFailureCode {
  invalidYear,
  invalidData,
  invalidated,
  overflow,
  persistence,
}

final class AnnualBudgetFailure implements Exception {
  const AnnualBudgetFailure(this.message, {required this.code});
  final String message;
  final AnnualBudgetFailureCode code;
  @override
  String toString() => message;
}

/// Suma firmada y partidas origen, sin perder presencia cuando el neto es cero.
/// Cero aritmético con budgetIds vacío significa «sin presupuesto».
final class AnnualBudgetTotal {
  AnnualBudgetTotal._(Iterable<BudgetRecord> records)
    : budgets = List.unmodifiable(records) {
    budgetIds = List.unmodifiable(budgets.map((record) => record.id));
    final sum = budgets.fold(
      BigInt.zero,
      (sum, record) => sum + BigInt.from(record.data.amountCents),
    );
    if (sum < BigInt.from(-9223372036854775808) ||
        sum > BigInt.from(9223372036854775807)) {
      throw const AnnualBudgetFailure(
        'Una cifra del presupuesto anual excede el rango int64.',
        code: AnnualBudgetFailureCode.overflow,
      );
    }
    amountCents = sum.toInt();
  }

  final List<BudgetRecord> budgets;
  late final List<String> budgetIds;
  late final int amountCents;
  int get budgetCount => budgets.length;
  bool get hasBudget => budgets.isNotEmpty;
}

/// La partida propia es independiente del agregado de toda la rama.
/// ownBudget null sigue siendo «sin presupuesto» propio aunque haya hijas.
/// Una partida del padre nunca genera partidas ni importes propios en hijos.
final class AnnualBudgetCell {
  const AnnualBudgetCell({
    required this.month,
    required this.ownBudget,
    required this.total,
  });
  final BudgetMonth month;
  final BudgetRecord? ownBudget;
  final AnnualBudgetTotal total;
  bool get hasOwnBudget => ownBudget != null;
  int? get ownAmountCents => ownBudget?.data.amountCents;
}

final class AnnualBudgetRow {
  AnnualBudgetRow._({required this.category, required this.months})
    : ownAnnualTotal = AnnualBudgetTotal._([
        for (final cell in months)
          if (cell.ownBudget != null) cell.ownBudget!,
      ]),
      annualTotal = AnnualBudgetTotal._([
        for (final cell in months) ...cell.total.budgets,
      ]);

  final CategoryDetails category;
  String get categoryId => category.node.id;

  /// Enero–diciembre, índice 0–11; lista inmutable.
  final List<AnnualBudgetCell> months;
  final AnnualBudgetTotal ownAnnualTotal, annualTotal;
}

/// Snapshot del año y árbol actual, incluidos nodos activos sin partidas y
/// archivados con partidas/antecesores. Preorden por nombre y UUID entre pares.
final class AnnualBudget {
  AnnualBudget._({
    required this.year,
    required Iterable<AnnualBudgetRow> rows,
    required this.months,
    required this.datasetState,
    required this.categoryGeneration,
  }) : rows = List.unmodifiable(rows),
       annualTotal = AnnualBudgetTotal._([
         for (final total in months) ...total.budgets,
       ]);

  final int year;
  final List<AnnualBudgetRow> rows;

  /// Totales de enero–diciembre: suma exclusivamente las raíces.
  final List<AnnualBudgetTotal> months;
  final AnnualBudgetTotal annualTotal;
  final DatasetState datasetState;
  final int categoryGeneration;
}

/// Sin caché ni captura. Releer tras guardar/importar o invalidar árbol/base.
/// Los repositorios y la unidad de lectura deben compartir conexión; app
/// recompone con la conexión nueva tras restaurar y la invalidación compartida.
final class AnnualBudgetQuery {
  AnnualBudgetQuery({
    required this._budgets,
    required this._categories,
    required this._unitOfWork,
  });

  final BudgetRepository _budgets;
  final CategoryManagement _categories;
  final UnitOfWork _unitOfWork;
  CategoryReadInvalidation get invalidation => _categories.invalidation;

  Future<AnnualBudget> read(int year) async {
    if (year < 1 || year > 9999) {
      throw const AnnualBudgetFailure(
        'Año inválido.',
        code: AnnualBudgetFailureCode.invalidYear,
      );
    }
    final generation = invalidation.generation;
    try {
      final result = await _unitOfWork.run(() async {
        // Fija el snapshot antes de leer árbol y partidas, sin mutar revisión.
        final state = await _unitOfWork.readState();
        final tree = await _categories.list();
        final records = await _budgets.readYear(year);
        return _assemble(year, tree, records, state, generation);
      });
      if (generation != invalidation.generation) {
        throw const AnnualBudgetFailure(
          'Los datos han cambiado. Vuelve a consultar el año.',
          code: AnnualBudgetFailureCode.invalidated,
        );
      }
      return result;
    } on AnnualBudgetFailure {
      rethrow;
    } catch (_) {
      throw const AnnualBudgetFailure(
        'No se pudo consultar el presupuesto anual. Inténtalo de nuevo.',
        code: AnnualBudgetFailureCode.persistence,
      );
    }
  }

  AnnualBudget _assemble(
    int year,
    List<CategoryDetails> tree,
    List<BudgetRecord> records,
    DatasetState state,
    int generation,
  ) {
    final nodes = <String, CategoryDetails>{};
    final children = <String?, List<CategoryDetails>>{};
    for (final category in tree) {
      final id = category.node.id;
      if (nodes.containsKey(id)) _invalid();
      nodes[id] = category;
      (children[category.node.parentId] ??= []).add(category);
    }
    List<String> ancestors(String start) {
      final path = <String>[];
      String? id = start;
      while (id != null) {
        final category = nodes[id];
        if (category == null || path.contains(id) || path.length == 3) {
          _invalid();
        }
        path.add(id);
        id = category.node.parentId;
      }
      if (nodes[start]!.node.depth != path.length) _invalid();
      return path;
    }

    final paths = {for (final id in nodes.keys) id: ancestors(id)};
    final own = <String, Map<int, BudgetRecord>>{};
    final recordIds = <String>{};
    for (final record in records) {
      final id = record.data.categoryId;
      final date = record.data.month.value;
      final month = int.parse(date.substring(5, 7)) - 1;
      if (!paths.containsKey(id) ||
          int.parse(date.substring(0, 4)) != year ||
          !recordIds.add(record.id) ||
          (own[id] ??= {}).containsKey(month)) {
        _invalid();
      }
      own[id]![month] = record;
    }
    // Rechaza una imagen inválida; nunca desglosa ni sustituye partidas.
    for (final entry in own.entries) {
      for (final ancestor in paths[entry.key]!.skip(1)) {
        if (entry.value.keys.any(
          (month) => own[ancestor]?.containsKey(month) ?? false,
        )) {
          _invalid();
        }
      }
    }
    final included = <String>{
      for (final category in tree)
        if (!category.node.archived) ...paths[category.node.id]!,
      for (final id in own.keys) ...paths[id]!,
    };
    final sums = <String, List<List<BudgetRecord>>>{
      for (final id in nodes.keys) id: List.generate(12, (_) => []),
    };
    // Cada partida se aporta una sola vez a cada antecesor, nunca a hijos.
    final sortedRecords = List<BudgetRecord>.of(records)
      ..sort((a, b) {
        final date = a.data.month.value.compareTo(b.data.month.value);
        return date == 0 ? a.id.compareTo(b.id) : date;
      });
    for (final record in sortedRecords) {
      final month = int.parse(record.data.month.value.substring(5, 7)) - 1;
      for (final id in paths[record.data.categoryId]!) {
        sums[id]![month].add(record);
      }
    }
    for (final siblings in children.values) {
      siblings.sort((a, b) {
        final name = a.node.name.compareTo(b.node.name);
        return name == 0 ? a.node.id.compareTo(b.node.id) : name;
      });
    }
    final rows = <AnnualBudgetRow>[];
    void visit(String? parentId) {
      for (final category in children[parentId] ?? <CategoryDetails>[]) {
        final id = category.node.id;
        if (included.contains(id)) {
          rows.add(
            AnnualBudgetRow._(
              category: category,
              months: List.unmodifiable(
                List.generate(
                  12,
                  (month) => AnnualBudgetCell(
                    month: BudgetMonth(year, month + 1),
                    ownBudget: own[id]?[month],
                    total: AnnualBudgetTotal._(sums[id]![month]),
                  ),
                ),
              ),
            ),
          );
        }
        visit(id);
      }
    }

    visit(null);
    final totals = List<AnnualBudgetTotal>.unmodifiable(
      List.generate(
        12,
        (month) => AnnualBudgetTotal._([
          for (final root in children[null] ?? <CategoryDetails>[])
            ...sums[root.node.id]![month],
        ]),
      ),
    );
    return AnnualBudget._(
      year: year,
      rows: rows,
      months: totals,
      datasetState: state,
      categoryGeneration: generation,
    );
  }
}

Never _invalid() => throw const AnnualBudgetFailure(
  'Los datos del presupuesto anual no son válidos.',
  code: AnnualBudgetFailureCode.invalidData,
);
