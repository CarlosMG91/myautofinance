import 'package:flutter/material.dart';

import '../../../ui/autofinance_ui.dart';
import '../domain/monthly_status_query.dart';
import '../domain/monthly_figure_detail.dart';

/// Proyección visual de EP-019. No agrega categorías ni reparte presupuestos.
class HomeSummary extends StatelessWidget {
  const HomeSummary({
    super.key,
    required this.data,
    required this.expanded,
    required this.categoryLabel,
    required this.details,
    required this.onRefresh,
    this.onDetail,
    this.onImport,
    this.onCategorize,
    this.supporting,
  });
  final MonthlyStatus data;
  final Set<String> expanded;
  final Widget Function(MonthlyStatusRow, Set<String>) categoryLabel;
  final MonthlyStatusDetailCallbacks details;
  final Future<void> Function() onRefresh;
  final Future<void> Function()? onDetail, onImport, onCategorize;
  final Widget? supporting;

  AfComparisonState comparison(MonthlyStatusTotals totals) => !totals.hasBudget
      ? AfComparisonState.unbudgeted
      : totals.differenceCents > 0
      ? AfComparisonState.favorable
      : totals.differenceCents < 0
      ? AfComparisonState.unfavorable
      : AfComparisonState.equal;

  @override
  Widget build(BuildContext context) {
    final period = data.month.value.substring(0, 7);
    final totalDetail = MonthlyFigureDetail(month: data.month);
    final byId = {for (final row in data.rows) row.categoryId: row};
    final parents = {
      for (final row in data.rows)
        if (row.category.node.parentId != null) row.category.node.parentId!,
    };
    bool visible(MonthlyStatusRow row) {
      var parent = row.category.node.parentId;
      while (parent != null) {
        if (!expanded.contains(parent)) return false;
        parent = byId[parent]?.category.node.parentId;
      }
      return true;
    }

    Widget chart(
      String title,
      MonthlyStatusTotals totals,
      MonthlyFigureDetail detail,
    ) => AfBarChart(
      title: title,
      period: period,
      data: [
        AfBarDatum(
          label: 'Real · $title',
          value: AfChartValue.euros(totals.actualCents),
          role: AfSeriesRole.real,
          onPressed: () => details.onMovements(detail),
        ),
        AfBarDatum(
          label: 'Presupuesto · $title',
          value: totals.hasBudget
              ? AfChartValue.euros(totals.plannedCents)
              : const AfChartValue.unbudgeted(),
          role: AfSeriesRole.budget,
          onPressed: detail.unclassified
              ? null
              : () => details.onBudgets(detail),
        ),
      ],
    );
    Widget category(
      String id,
      String label,
      MonthlyStatusTotals totals,
      MonthlyFigureDetail detail, {
      MonthlyStatusRow? row,
    }) => Column(
      key: ValueKey('home-category:$id'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        if (row != null)
          categoryLabel(row, parents)
        else
          Text(label, style: Theme.of(context).textTheme.titleMedium),
        chart(label, totals, detail),
        AfValueRow(
          label: 'Diferencia real − presupuesto',
          value: AfMoneyText(AfAmount(totals.differenceCents)),
          onPressed: () => details.onDifference(detail),
        ),
        AfComparisonBadge(comparison(totals)),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 24,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            AfAction(
              label: 'Importar CSV',
              icon: AfIcons.importFile,
              onPressed: onImport,
              unavailableReason: 'Servicio local no disponible.',
            ),
            AfAction(
              label: 'Ver detalle',
              key: const ValueKey('home-detail'),
              icon: AfIcons.analysis,
              onPressed: onDetail,
            ),
            AfAction(
              label: 'Actualizar',
              onPressed: onRefresh,
              variant: AfActionVariant.link,
            ),
          ],
        ),
        AfResponsiveGrid(
          children: [
            AfSummaryCard(
              label: 'Resultado real del mes',
              amount: AfAmount(data.total.actualCents),
              tone: AfCardTone.real,
              contextLabel:
                  'Suma firmada de movimientos · $period · no es un saldo',
              onDetail: onDetail,
            ),
            if (!data.total.hasBudget)
              AfCard(
                tone: AfCardTone.budget,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: [
                    const Text('Resultado presupuestado'),
                    const Text('Sin presupuesto'),
                    Text('Partidas del mes seleccionado · $period'),
                    AfAction(
                      label: 'Ver detalle',
                      variant: AfActionVariant.link,
                      onPressed: () => details.onBudgets(totalDetail),
                    ),
                  ],
                ),
              )
            else
              AfSummaryCard(
                label: 'Resultado presupuestado',
                amount: AfAmount(data.total.plannedCents),
                tone: AfCardTone.budget,
                contextLabel: 'Partidas del mes seleccionado · $period',
                onDetail: () => details.onBudgets(totalDetail),
              ),
            AfSummaryCard(
              label: 'Diferencia real − presupuesto',
              amount: AfAmount(data.total.differenceCents),
              contextLabel: data.total.hasBudget
                  ? 'Comparación algebraica · $period'
                  : 'Sin presupuesto: aporta cero a la diferencia · $period',
              comparison: comparison(data.total),
              onDetail: () => details.onDifference(totalDetail),
            ),
          ],
        ),
        if (!data.total.hasMovements)
          const AfStatus(
            kind: AfStatusKind.empty,
            message: 'No hay movimientos en este mes. Real: 0,00 €.',
          ),
        AfResponsiveGrid(
          columns: 2,
          minimumWidth: 420,
          children: [
            chart('Real y presupuesto', data.total, totalDetail),
            ?supporting,
          ],
        ),
        Text(
          'Pendientes del mes',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        AfCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Text(
                '${data.unclassified.movementCount} movimientos sin categorizar · $period',
              ),
              Text(
                data.unclassified.hasMovements
                    ? 'Asigna una categoría desde los movimientos o la bandeja.'
                    : 'Todos los movimientos del mes tienen categoría.',
              ),
              AfAction(
                label: 'Categorizar pendientes',
                icon: AfIcons.category,
                onPressed: onCategorize,
                unavailableReason: 'Servicio local no disponible.',
              ),
              const Text(
                'La bandeja de categorización reúne pendientes de todos los meses.',
              ),
            ],
          ),
        ),
        Text('Por categoría', style: Theme.of(context).textTheme.titleLarge),
        const Text(
          'Todas las cuentas · ramas actuales. Cada agregado incluye sus descendientes una sola vez. Abre Ver detalle para consultar también el real directo.',
        ),
        AfResponsiveGrid(
          columns: 2,
          minimumWidth: 420,
          children: [
            for (final row in data.rows.where(visible))
              category(
                row.categoryId,
                row.category.path,
                row.totals,
                MonthlyFigureDetail(
                  month: data.month,
                  categoryId: row.categoryId,
                ),
                row: row,
              ),
            if (data.unclassified.hasMovements)
              category(
                'sin-clasificar',
                'Sin clasificar',
                data.unclassified,
                MonthlyFigureDetail(month: data.month, unclassified: true),
              ),
          ],
        ),
      ],
    );
  }
}
