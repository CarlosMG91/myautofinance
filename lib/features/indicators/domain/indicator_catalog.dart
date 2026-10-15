import 'indicator_definition.dart';

/// Registro explícito, sin persistencia, plugins ni evaluación de strings.
final class IndicatorCatalog {
  IndicatorCatalog(Iterable<IndicatorDefinition> definitions)
    : definitions = List.unmodifiable(definitions) {
    final ids = <String>{};
    for (final definition in this.definitions) {
      if (!ids.add(definition.id)) {
        throw ArgumentError('ID de indicador duplicado: ${definition.id}.');
      }
    }
  }

  factory IndicatorCatalog.v1() => IndicatorCatalog([
    IndicatorDefinition(
      id: 'colchon_emergencia',
      name: 'Colchón de emergencia',
      version: 1,
      requiredInputs: {
        IndicatorInput.monthlyWealth,
        IndicatorInput.annualIncomeBudget,
      },
      period: IndicatorPeriod.month,
      unit: 'meses',
      reasons: [
        IndicatorReason(
          code: 'foto_ausente',
          text: 'sin dato: falta foto patrimonial',
        ),
        IndicatorReason(
          code: 'foto_incompleta',
          text: 'sin dato: foto patrimonial incompleta',
        ),
        IndicatorReason(
          code: 'ingresos_incompletos',
          text: 'sin dato: presupuesto anual de ingresos incompleto',
        ),
        IndicatorReason(
          code: 'ingresos_nulos',
          text: 'sin dato: ingresos presupuestados nulos',
        ),
        IndicatorReason(
          code: 'ingresos_negativos',
          text: 'sin dato: ingresos presupuestados no positivos',
        ),
      ],
    ),
  ]);

  final List<IndicatorDefinition> definitions;

  IndicatorDefinition definition(String id) => definitions.firstWhere(
    (definition) => definition.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'Indicador desconocido'),
  );
}
