import '../../wealth/wealth.dart' show Month;
import 'indicator_catalog.dart';
import 'indicator_definition.dart';
import 'indicator_inputs.dart';
import 'indicator_result.dart';

abstract interface class IndicatorCalculation {
  /// Función de dominio sobre entradas tipadas, nunca sobre texto formateado.
  /// Respeta los motivos y su precedencia declarados en la definición.
  IndicatorResult calculate(IndicatorInputs inputs);
}

final class IndicatorEvaluation {
  const IndicatorEvaluation({
    required this.definition,
    required this.month,
    required this.result,
  });

  final IndicatorDefinition definition;
  final Month month;
  final IndicatorResult result;
}

final class IndicatorEngine {
  IndicatorEngine({
    required this.catalog,
    required this._inputs,
    required Map<String, IndicatorCalculation> calculations,
  }) : _calculations = Map.unmodifiable(calculations) {
    final ids = catalog.definitions.map((definition) => definition.id).toSet();
    if (ids.length != calculations.length ||
        !ids.containsAll(calculations.keys)) {
      throw ArgumentError('El catálogo y los cálculos deben coincidir.');
    }
  }

  final IndicatorCatalog catalog;
  final IndicatorInputProvider _inputs;
  final Map<String, IndicatorCalculation> _calculations;

  Future<IndicatorEvaluation> evaluate(String id, Month month) async {
    final definition = catalog.definition(id);
    final inputs = await _read(month, definition.requiredInputs);
    final result = _calculations[id]!.calculate(inputs);
    // Un incumplimiento del cálculo no se disfraza de ausencia financiera.
    switch (result) {
      case CalculatedIndicator():
        if (result.unit != definition.unit) {
          throw StateError('Unidad de resultado ajena a $id.');
        }
      case UnavailableIndicator():
        if (!definition.reasons.any(
          (reason) => reason.code == result.code && reason.text == result.text,
        )) {
          throw StateError('Motivo de resultado ajeno a $id.');
        }
    }
    return IndicatorEvaluation(
      definition: definition,
      month: month,
      result: result,
    );
  }

  Future<IndicatorInputs> _read(
    Month month,
    Set<IndicatorInput> requiredInputs,
  ) async {
    final IndicatorInputs inputs;
    try {
      inputs = await _inputs.read(month, requiredInputs);
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
    final wealth = inputs.wealth;
    final income = inputs.annualIncome;
    if (inputs.month.value != month.value ||
        (wealth != null && wealth.month.value != month.value) ||
        (income != null &&
            income.year != int.parse(month.value.substring(0, 4))) ||
        (requiredInputs.contains(IndicatorInput.monthlyWealth) &&
            wealth == null) ||
        (requiredInputs.contains(IndicatorInput.annualIncomeBudget) &&
            income == null)) {
      throw const IndicatorReadFailure(
        code: IndicatorReadFailureCode.invalidInputs,
        message: 'Las entradas no corresponden al periodo o faltan lecturas.',
      );
    }
    return inputs;
  }
}
