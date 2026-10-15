import '../../../core/persistence/unit_of_work.dart';
import '../../movements/movements.dart';
import 'budget_repository.dart';

final class BudgetListQuery {
  BudgetListQuery({
    required this.month,
    this.categoryId,
    this.unclassified = false,
    this.scope = MovementCategoryScope.branch,
  }) : firstMonth = month,
       lastMonth = month {
    _validateCategory();
  }

  /// El mes enfocado es contexto de captura; no limita el detalle del año.
  BudgetListQuery.annual(
    int year, {
    int focusedMonth = 1,
    this.categoryId,
    this.unclassified = false,
    this.scope = MovementCategoryScope.branch,
  }) : month = BudgetMonth(year, focusedMonth),
       firstMonth = BudgetMonth(year, 1),
       lastMonth = BudgetMonth(year, 12) {
    _validateCategory();
  }

  /// Rango inclusivo, también entre años. month conserva el contexto de captura.
  BudgetListQuery.range({
    required this.month,
    required this.firstMonth,
    required this.lastMonth,
    this.categoryId,
    this.unclassified = false,
    this.scope = MovementCategoryScope.branch,
  }) {
    if (firstMonth.value.compareTo(lastMonth.value) > 0) {
      throw const BudgetFailure('Rango de partidas inválido.');
    }
    _validateCategory();
  }

  void _validateCategory() {
    if (unclassified) {
      throw const BudgetFailure('El presupuesto no admite Sin clasificar.');
    }
    if (categoryId != null &&
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(categoryId!)) {
      throw const BudgetFailure('Identificador de categoría inválido.');
    }
  }

  final BudgetMonth month;
  final BudgetMonth firstMonth, lastMonth;
  int get year => int.parse(month.value.substring(0, 4));
  bool get isAnnual =>
      firstMonth.value.substring(0, 4) == lastMonth.value.substring(0, 4) &&
      firstMonth.value.substring(5, 7) == '01' &&
      lastMonth.value.substring(5, 7) == '12';
  bool get isMonthly => firstMonth.value == lastMonth.value;
  bool includesMonth(BudgetMonth value) =>
      value.value.compareTo(firstMonth.value) >= 0 &&
      value.value.compareTo(lastMonth.value) <= 0;
  final String? categoryId;

  /// Compatibilidad con llamadas anteriores; true se rechaza al construir.
  final bool unclassified;
  final MovementCategoryScope scope;
}

final class BudgetListEntry {
  const BudgetListEntry(this.record, this.category);
  final BudgetRecord record;
  final CategoryDetails category;
}

/// Resultado de una sola lectura coherente. Conserva ceros y procedencia.
/// Las páginas se obtienen en memoria, sin releer subtotal ni consultar SQLite.
/// Releer tras mutaciones: este resultado no representa cambios posteriores.
final class BudgetListResult {
  BudgetListResult._({
    required this.query,
    required List<BudgetListEntry> entries,
    required this.datasetState,
    required this.categoryGeneration,
  }) : entries = List.unmodifiable(entries),
       subtotalCents = entries.fold<BigInt>(
         BigInt.zero,
         (sum, entry) => sum + BigInt.from(entry.record.data.amountCents),
       );

  final BudgetListQuery query;
  final List<BudgetListEntry> entries;
  final DatasetState datasetState;
  final int categoryGeneration;
  final BigInt subtotalCents;
  int get totalCount => entries.length;
  static const maxPageSize = 200;

  /// offset es un índice en este resultado, nunca en una consulta posterior.
  /// Un offset igual o mayor al contador devuelve una página vacía.
  List<BudgetListEntry> page({int offset = 0, int limit = 100}) {
    if (offset < 0 || limit < 1 || limit > maxPageSize) {
      throw const BudgetFailure('Página inválida: usa entre 1 y 200 partidas.');
    }
    if (offset >= totalCount) return const [];
    final end = offset + limit;
    return List.unmodifiable(
      entries.sublist(offset, end > totalCount ? totalCount : end),
    );
  }
}

/// Lista de partidas originales, sin materializar ausencias o repartir padres.
/// Una lectura mensual o una por año del intervalo, dentro de la misma unidad
/// de lectura que el árbol. Materializa el ámbito completo para que páginas y
/// subtotal siempre correspondan a los mismos registros.
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

  Future<List<BudgetListEntry>> read(BudgetListQuery query) async =>
      (await readResult(query)).entries;

  Future<BudgetListResult> readResult(BudgetListQuery query) async {
    final generation = invalidation.generation;
    try {
      final result = await _unitOfWork.run(() async {
        final state = await _unitOfWork.readState();
        final nodes = {for (final c in await _categories.list()) c.node.id: c};
        if (query.categoryId != null && !nodes.containsKey(query.categoryId)) {
          throw const BudgetFailure(
            'La categoría no existe.',
            code: BudgetFailureCode.categoryNotFound,
          );
        }
        bool includes(String id) {
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
        final ids = <String>{};
        final firstYear = int.parse(query.firstMonth.value.substring(0, 4));
        final lastYear = int.parse(query.lastMonth.value.substring(0, 4));
        for (var year = firstYear; year <= lastYear; year++) {
          final records = query.isMonthly
              ? await _budgets.list(query.firstMonth)
              : await _budgets.readYear(year);
          for (final record in records) {
            final category = nodes[record.data.categoryId];
            if (category == null ||
                !ids.add(record.id) ||
                int.parse(record.data.month.value.substring(0, 4)) != year ||
                query.isMonthly && !query.includesMonth(record.data.month)) {
              throw const BudgetFailure('Partida de presupuesto inválida.');
            }
            if (query.includesMonth(record.data.month) &&
                includes(category.node.id)) {
              entries.add(BudgetListEntry(record, category));
            }
          }
        }
        entries.sort((a, b) {
          final month = a.record.data.month.value.compareTo(
            b.record.data.month.value,
          );
          if (month != 0) return month;
          final path = a.category.path.compareTo(b.category.path);
          return path == 0 ? a.record.id.compareTo(b.record.id) : path;
        });
        return BudgetListResult._(
          query: query,
          entries: entries,
          datasetState: state,
          categoryGeneration: generation,
        );
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
