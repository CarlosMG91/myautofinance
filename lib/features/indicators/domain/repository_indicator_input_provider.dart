import '../../../core/persistence/unit_of_work.dart';
import '../../budget/budget.dart';
import '../../wealth/wealth.dart';
import 'indicator_definition.dart';
import 'indicator_inputs.dart';

/// Los repositorios y la unidad de lectura deben compartir conexión.
/// Sin caché: app recompone el proveedor tras sustituir la base de la sesión.
final class RepositoryIndicatorInputProvider implements IndicatorInputProvider {
  RepositoryIndicatorInputProvider({
    required this._wealth,
    required this._budgets,
    required this._unitOfWork,
  });

  final WealthManagement _wealth;
  final BudgetRepository _budgets;
  final UnitOfWork _unitOfWork;

  @override
  Future<IndicatorInputs> read(
    Month month,
    Set<IndicatorInput> requiredInputs,
  ) async {
    final requested = Set<IndicatorInput>.of(requiredInputs);
    try {
      return await _unitOfWork.run(() async {
        // La primera consulta fija el snapshot antes de leer fotos y catálogo.
        final state = await _unitOfWork.readState();
        final wealth = requested.contains(IndicatorInput.monthlyWealth)
            ? await _wealth.readMonth(month)
            : null;
        if (wealth != null && wealth.month.value != month.value) _invalid();
        AnnualIncomeBudget? income;
        if (requested.contains(IndicatorInput.annualIncomeBudget)) {
          final year = int.parse(month.value.substring(0, 4));
          // La selección por raíz actual y la exclusión padre/descendiente
          // pertenecen al repositorio; no se infiere ingreso por el signo.
          final records = await _budgets.readYear(year, incomeOnly: true);
          var total = BigInt.zero;
          final present = <int>{};
          final ids = <String>{};
          for (final record in records) {
            final date = record.data.month.value;
            if (int.parse(date.substring(0, 4)) != year ||
                !ids.add(record.id)) {
              _invalid();
            }
            present.add(int.parse(date.substring(5, 7)));
            total += BigInt.from(record.data.amountCents);
          }
          income = AnnualIncomeBudget(
            year: year,
            totalCents: total,
            presentMonths: present,
            sourceBudgets: records,
          );
        }
        return IndicatorInputs(
          month: month,
          wealth: wealth,
          annualIncome: income,
          datasetState: state,
        );
      });
    } on IndicatorReadFailure {
      rethrow;
    } catch (error, stack) {
      Error.throwWithStackTrace(
        IndicatorReadFailure(
          code: IndicatorReadFailureCode.read,
          message: 'No se pudieron leer las entradas del indicador.',
          cause: error,
        ),
        stack,
      );
    }
  }

  Never _invalid() => throw const IndicatorReadFailure(
    code: IndicatorReadFailureCode.invalidInputs,
    message: 'Las entradas no corresponden al periodo o contienen duplicados.',
  );
}
