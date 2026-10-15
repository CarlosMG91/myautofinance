/// Identidades de entradas de dominio, nunca nombres de tablas o fórmulas.
enum IndicatorInput { monthlyWealth, annualIncomeBudget }

enum IndicatorPeriod { month, year }

final class IndicatorReason {
  IndicatorReason({required this.code, required this.text}) {
    if (code.trim().isEmpty || text.trim().isEmpty) {
      throw ArgumentError('El motivo necesita código y texto.');
    }
  }

  final String code, text;
}

/// Metadatos en código. El cálculo se inyecta por separado en el motor.
final class IndicatorDefinition {
  IndicatorDefinition({
    required this.id,
    required this.name,
    required this.version,
    required Set<IndicatorInput> requiredInputs,
    required this.period,
    required this.unit,
    required List<IndicatorReason> reasons,
  }) : requiredInputs = Set.unmodifiable(requiredInputs),
       reasons = List.unmodifiable(reasons) {
    if (id.trim().isEmpty ||
        name.trim().isEmpty ||
        unit.trim().isEmpty ||
        version < 1) {
      throw ArgumentError('Definición de indicador inválida.');
    }
    if (reasons.map((reason) => reason.code).toSet().length != reasons.length) {
      throw ArgumentError('Códigos de motivo duplicados en $id.');
    }
  }

  final String id, name, unit;
  final int version;
  final Set<IndicatorInput> requiredInputs;
  final IndicatorPeriod period;

  /// Orden de precedencia obligatorio para la implementación del cálculo.
  final List<IndicatorReason> reasons;
}
