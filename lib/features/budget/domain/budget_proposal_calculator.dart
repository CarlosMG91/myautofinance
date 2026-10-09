import '../../../core/persistence/unit_of_work.dart';
import '../../movements/movements.dart';
import 'budget_proposal.dart';
import 'budget_repository.dart';

/// Todos los repositorios comparten conexión con unitOfWork. Sin caché ni
/// escrituras: los reales completos de EP-010 se suman una sola vez por raíz.
final class BudgetProposalCalculator {
  BudgetProposalCalculator({
    required this._movements,
    required this._categories,
    required this._budgets,
    required this._unitOfWork,
  });
  final MovementRepository _movements;
  final CategoryManagement _categories;
  final BudgetRepository _budgets;
  final UnitOfWork _unitOfWork;

  static final _minimum = BigInt.parse('-9223372036854775808');
  static final _maximum = BigInt.parse('9223372036854775807');
  static final _step = BigInt.from(1000);

  Future<BudgetProposalDraft> calculate(int sourceYear) async {
    if (sourceYear < 1 || sourceYear >= 9999) {
      throw BudgetProposalFailure(
        sourceYear == 9999
            ? 'El año 9999 no tiene un año siguiente válido.'
            : 'El año fuente debe estar entre 1 y 9998.',
        code: BudgetProposalFailureCode.invalidSourceYear,
      );
    }
    try {
      return await _unitOfWork.run(() async {
        final state = await _unitOfWork.readState();
        final categories = await _categories.list();
        final byId = {for (final c in categories) c.node.id: c};
        final roots =
            categories
                .where((c) => c.node.parentId == null && !c.node.archived)
                .toList()
              ..sort((a, b) {
                final path = a.path.compareTo(b.path);
                return path == 0 ? a.node.id.compareTo(b.node.id) : path;
              });
        CategoryDetails rootOf(String id) {
          var current = byId[id];
          final seen = <String>{};
          while (current != null) {
            if (!seen.add(current.node.id)) {
              throw StateError('Ciclo de categorías.');
            }
            final parent = current.node.parentId;
            if (parent == null) return current;
            current = byId[parent];
          }
          throw StateError('Categoría ausente.');
        }

        final source = (await _movements.readYear(sourceYear))
            .map(BudgetProposalSourceReal.fromRecord)
            .toList();
        final totals = <(String, int), BigInt>{};
        final counts = <(String, int), int>{};
        final excluded = <BudgetProposalExcludedReal>[];
        for (final real in source) {
          final id = real.categoryId;
          if (id == null || rootOf(id).node.archived) {
            excluded.add(
              BudgetProposalExcludedReal(
                real: real,
                reason: id == null
                    ? BudgetProposalExclusionReason.unclassified
                    : BudgetProposalExclusionReason.archivedRoot,
                categoryPath: id == null ? null : byId[id]!.path,
              ),
            );
            continue;
          }
          final key = (
            rootOf(id).node.id,
            int.parse(real.valueDate.substring(5, 7)),
          );
          totals[key] =
              (totals[key] ?? BigInt.zero) + BigInt.from(real.amountCents);
          counts[key] = (counts[key] ?? 0) + 1;
        }
        excluded.sort((a, b) {
          final date = a.real.valueDate.compareTo(b.real.valueDate);
          return date == 0 ? a.real.id.compareTo(b.real.id) : date;
        });
        final rows = <BudgetProposalRow>[];
        for (final root in roots) {
          for (var month = 1; month <= 12; month++) {
            final key = (root.node.id, month);
            final total = totals[key] ?? BigInt.zero;
            final magnitude =
                ((total.abs() + _step - BigInt.one) ~/ _step) * _step;
            rows.add(
              BudgetProposalRow(
                root: root,
                sourceMonth: BudgetMonth(sourceYear, month),
                targetMonth: BudgetMonth(sourceYear + 1, month),
                sourceAmountCents: _exactCents(total),
                proposedAmountCents: _exactCents(
                  total.isNegative ? -magnitude : magnitude,
                ),
                sourceMovementCount: counts[key] ?? 0,
              ),
            );
          }
        }
        final rootIds = roots.map((r) => r.node.id).toSet();
        final targetBudgets = (await _budgets.readYear(sourceYear + 1))
            .where((r) => rootIds.contains(rootOf(r.data.categoryId).node.id));
        return BudgetProposalDraft(
          sourceYear: sourceYear,
          targetYear: sourceYear + 1,
          sourceRows: rows,
          allocations: rows.map(
            (r) => BudgetInput(
              month: r.targetMonth,
              categoryId: r.categoryId,
              amountCents: r.proposedAmountCents,
            ),
          ),
          includedScopes: rows.map(
            (r) =>
                BudgetProposalScope(rootId: r.categoryId, month: r.targetMonth),
          ),
          excludedReals: excluded,
          basis: BudgetProposalBasis(
            sourceYear: sourceYear,
            datasetState: state,
            categories: categories,
            sourceReals: source,
            targetBudgets: targetBudgets,
          ),
        );
      });
    } on BudgetProposalFailure {
      rethrow;
    } catch (_) {
      throw const BudgetProposalFailure(
        'No se pudo calcular la propuesta de presupuesto. Inténtalo de nuevo.',
        code: BudgetProposalFailureCode.persistence,
      );
    }
  }

  static int _exactCents(BigInt value) {
    if (value < _minimum || value > _maximum) {
      throw const BudgetProposalFailure(
        'El real agregado o su propuesta excede el rango de céntimos permitido.',
        code: BudgetProposalFailureCode.overflow,
      );
    }
    return value.toInt();
  }
}
