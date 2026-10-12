import '../../../core/persistence/unit_of_work.dart';
import '../../movements/movements.dart';

enum AnnualActualFailureCode {
  invalidYear,
  invalidData,
  invalidated,
  overflow,
  persistence,
}

final class AnnualActualFailure implements Exception {
  const AnnualActualFailure(this.message, {required this.code});
  final String message;
  final AnnualActualFailureCode code;
  @override
  String toString() => message;
}

/// Céntimos firmados exactos y presencia independiente del importe neto.
final class AnnualActualTotal {
  const AnnualActualTotal({
    required this.amountCents,
    required this.movementCount,
  });
  final int amountCents, movementCount;
  bool get hasMovements => movementCount > 0;
}

/// Origen por año del snapshot, mes 1–12 y categoría/alcance de la fila.
/// direct solo incluye el nodo; total incluye sus descendientes una vez.
final class AnnualActualCell {
  const AnnualActualCell({
    required this.month,
    required this.direct,
    required this.total,
  });
  final int month;
  final AnnualActualTotal direct, total;
}

final class AnnualActualRow {
  AnnualActualRow._({
    required this.category,
    required Iterable<AnnualActualCell> months,
  }) : months = List.unmodifiable(months) {
    directAnnualTotal = _sum(this.months.map((cell) => cell.direct));
    annualTotal = _sum(this.months.map((cell) => cell.total));
  }

  /// null solo para el grupo de informe Sin clasificar, fuera del árbol.
  final CategoryDetails? category;
  String? get categoryId => category?.node.id;
  final List<AnnualActualCell> months;
  late final AnnualActualTotal directAnnualTotal, annualTotal;
}

/// Snapshot inmutable de doce meses y árbol actual. Preorden nombre/UUID:
/// raíces activas, nodos con movimientos y antecesores, incluidos archivados.
final class AnnualActual {
  AnnualActual._({
    required this.year,
    required Iterable<CategoryDetails> tree,
    required Iterable<AnnualActualRow> rows,
    required this.unclassified,
    required Iterable<AnnualActualTotal> months,
    required this.datasetState,
    required this.categoryGeneration,
  }) : tree = List.unmodifiable(tree),
       rows = List.unmodifiable(rows),
       months = List.unmodifiable(months) {
    annualTotal = _sum(this.months);
  }

  final int year;
  final List<CategoryDetails> tree;
  final List<AnnualActualRow> rows;
  final AnnualActualRow unclassified;

  /// Enero–diciembre; raíces + Sin clasificar, sin volver a sumar hijos.
  final List<AnnualActualTotal> months;
  late final AnnualActualTotal annualTotal;
  final DatasetState datasetState;
  final int categoryGeneration;
}

/// Sin caché ni escrituras. Releer tras modificar/importar o invalidar catálogo.
/// Compartir conexión en todos los puertos; recomponer tras reemplazar la base.
final class AnnualActualQuery {
  AnnualActualQuery({
    required this._movements,
    required this._categories,
    required this._unitOfWork,
  });

  final AnnualMovementTotalsReader _movements;
  final CategoryManagement _categories;
  final UnitOfWork _unitOfWork;
  CategoryReadInvalidation get invalidation => _categories.invalidation;

  Future<AnnualActual> read(int year) async {
    if (year < 1 || year > 9999) {
      throw const AnnualActualFailure(
        'Año inválido.',
        code: AnnualActualFailureCode.invalidYear,
      );
    }
    final generation = invalidation.generation;
    try {
      final result = await _unitOfWork.run(() async {
        // Primera lectura: fija la misma identidad/revisión para árbol y reales.
        final state = await _unitOfWork.readState();
        final tree = await _categories.list();
        final totals = await _movements.readYearTotals(year);
        return _assemble(year, tree, totals, state, generation);
      });
      if (generation != invalidation.generation) {
        throw const AnnualActualFailure(
          'Los datos han cambiado. Vuelve a consultar el año.',
          code: AnnualActualFailureCode.invalidated,
        );
      }
      return result;
    } on AnnualActualFailure {
      rethrow;
    } on MovementTotalsOverflow {
      throw _overflow();
    } catch (_) {
      throw const AnnualActualFailure(
        'No se pudo consultar el real anual. Inténtalo de nuevo.',
        code: AnnualActualFailureCode.persistence,
      );
    }
  }

  AnnualActual _assemble(
    int year,
    List<CategoryDetails> tree,
    List<AnnualMovementTotal> totals,
    DatasetState state,
    int generation,
  ) {
    final nodes = <String, CategoryDetails>{};
    final children = <String?, List<CategoryDetails>>{};
    for (final category in tree) {
      if (nodes.containsKey(category.node.id)) _invalid();
      nodes[category.node.id] = category;
      (children[category.node.parentId] ??= []).add(category);
    }
    // Valida incluso ramas vacías antes de usar el agrupador compartido.
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
    final included = <String>{
      for (final category in tree)
        if (category.node.parentId == null && !category.node.archived)
          category.node.id,
    };
    final direct = List.generate(12, (_) => <String?, AnnualActualTotal>{});
    for (final total in totals) {
      if (total.month < 1 || total.month > 12 || total.movementCount <= 0) {
        _invalid();
      }
      final month = direct[total.month - 1];
      final id = total.categoryId;
      if (month.containsKey(id)) _invalid();
      month[id] = AnnualActualTotal(
        amountCents: total.amountCents,
        movementCount: total.movementCount,
      );
      if (id != null) {
        if (!paths.containsKey(id)) _invalid();
        included.addAll(paths[id]!);
      }
    }
    final grouping = CategoryGrouping(tree);
    final aggregate = [
      for (final month in direct)
        grouping.aggregateExact({
          for (final entry in month.entries)
            if (entry.key != null)
              entry.key!: BigInt.from(entry.value.amountCents),
        }),
    ];
    final counts = [
      for (final month in direct)
        grouping.aggregateExact({
          for (final entry in month.entries)
            if (entry.key != null)
              entry.key!: BigInt.from(entry.value.movementCount),
        }),
    ];
    AnnualActualRow buildRow(CategoryDetails? category) {
      final id = category?.node.id;
      return AnnualActualRow._(
        category: category,
        months: List.generate(12, (index) {
          final own = direct[index][id] ?? _zero;
          return AnnualActualCell(
            month: index + 1,
            direct: own,
            total: id == null
                ? own
                : AnnualActualTotal(
                    amountCents: _checked(aggregate[index][id]!),
                    movementCount: _checked(counts[index][id]!),
                  ),
          );
        }),
      );
    }

    for (final siblings in children.values) {
      siblings.sort((a, b) {
        final name = a.node.name.compareTo(b.node.name);
        return name == 0 ? a.node.id.compareTo(b.node.id) : name;
      });
    }
    final rows = <AnnualActualRow>[];
    void visit(String? parent) {
      for (final category in children[parent] ?? <CategoryDetails>[]) {
        if (included.contains(category.node.id)) rows.add(buildRow(category));
        visit(category.node.id);
      }
    }

    visit(null);
    final unclassified = buildRow(null);
    return AnnualActual._(
      year: year,
      tree: tree,
      rows: rows,
      unclassified: unclassified,
      months: List.generate(
        12,
        (index) => _sum([
          unclassified.months[index].total,
          for (final row in rows)
            if (row.category!.node.parentId == null) row.months[index].total,
        ]),
      ),
      datasetState: state,
      categoryGeneration: generation,
    );
  }
}

const _zero = AnnualActualTotal(amountCents: 0, movementCount: 0);

AnnualActualTotal _sum(Iterable<AnnualActualTotal> totals) {
  var amount = BigInt.zero, count = BigInt.zero;
  for (final total in totals) {
    amount += BigInt.from(total.amountCents);
    count += BigInt.from(total.movementCount);
  }
  return AnnualActualTotal(
    amountCents: _checked(amount),
    movementCount: _checked(count),
  );
}

final _min = BigInt.parse('-9223372036854775808');
final _max = BigInt.parse('9223372036854775807');
int _checked(BigInt value) {
  if (value < _min || value > _max) throw _overflow();
  return value.toInt();
}

AnnualActualFailure _overflow() => const AnnualActualFailure(
  'Una cifra del real anual excede el rango int64.',
  code: AnnualActualFailureCode.overflow,
);

Never _invalid() => throw const AnnualActualFailure(
  'Los datos del año o el árbol de categorías no son coherentes.',
  code: AnnualActualFailureCode.invalidData,
);
