import 'package:flutter/material.dart';

import '../../../ui/autofinance_ui.dart';
import '../domain/annual_budget_query.dart';
import 'budget_ui.dart';

/// Proyección del mismo snapshot que la matriz: solo las raíces aportan totales.
class AnnualBudgetSummary extends StatelessWidget {
  const AnnualBudgetSummary({
    super.key,
    required this.data,
    required this.focusedMonth,
    required this.monthLabel,
    required this.onMonth,
    required this.onYear,
    required this.onDetail,
    this.detailFocus,
  });

  final AnnualBudget data;
  final int focusedMonth;
  final String monthLabel;
  final VoidCallback? onMonth, onDetail;
  final FocusNode? detailFocus;
  final void Function(String? categoryId)? onYear;

  AfAmount _amount(AnnualBudgetTotal total) => total.hasBudget
      ? AfAmount(total.amountCents)
      : const AfAmount.missing('sin presupuesto');

  @override
  Widget build(BuildContext context) {
    final roots = data.rows.where((row) => row.category.node.depth == 1);
    final incomes = roots.where((row) => row.category.node.isIncome);
    final incomeCount = incomes.fold(
      0,
      (n, row) => n + row.annualTotal.budgetCount,
    );
    final income = incomes.fold(
      BigInt.zero,
      (n, row) => n + BigInt.from(row.annualTotal.amountCents),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 24,
      children: [
        AfResponsiveGrid(
          children: [
            AfSummaryCard(
              key: const Key('budget-summary-year'),
              label: 'Resultado presupuestado del año',
              amount: _amount(data.annualTotal),
              contextLabel:
                  '${data.year} · ${data.annualTotal.budgetCount} partidas · Suma de doce meses',
              tone: AfCardTone.budget,
            ),
            AfCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  const Text('Ingresos presupuestados'),
                  Text(
                    budgetTotal(incomeCount == 0 ? null : income),
                    style:
                        (AfTokens.reflow(
                                  context,
                                  MediaQuery.sizeOf(context).width,
                                )
                                ? Theme.of(context).textTheme.bodyLarge
                                : Theme.of(context).textTheme.headlineMedium)
                            ?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                  ),
                  const Text(
                    'Categorías con raíz marcada Ingreso · Año completo',
                  ),
                ],
              ),
            ),
            AfSummaryCard(
              key: const Key('budget-summary-month'),
              label: 'Mes enfocado',
              amount: _amount(data.months[focusedMonth - 1]),
              contextLabel:
                  '$monthLabel ${data.year} · ${data.months[focusedMonth - 1].budgetCount} partidas',
              tone: AfCardTone.budget,
              onDetail: onMonth,
            ),
          ],
        ),
        AfPageHeader(
          title: 'Partidas del año',
          actions: [
            OutlinedButton(
              key: const Key('budget-show-detail'),
              focusNode: detailFocus,
              onPressed: onDetail,
              child: const Text('Ver detalle'),
            ),
          ],
        ),
        if (!data.annualTotal.hasBudget)
          const AfStatus(
            kind: AfStatusKind.empty,
            message: 'Este año no tiene partidas. Abre la captura mensual para empezar.',
          ),
        AfResponsiveGrid(
          columns: 2,
          children: [
            for (final root in roots)
              AfCard(
                key: ValueKey('budget-summary-${root.categoryId}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: [
                    Text(
                      root.category.node.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${root.category.node.isIncome ? 'Ingreso' : 'Salida'}${root.category.node.archived ? ' · Archivada' : ''}',
                    ),
                    AfMoneyText(_amount(root.annualTotal), hero: true),
                    Text(
                      '${root.annualTotal.budgetCount} partidas · ${data.year}',
                    ),
                    AfValueRow(
                      label: monthLabel,
                      value: AfMoneyText(
                        _amount(root.months[focusedMonth - 1].total),
                      ),
                    ),
                    AfAction(
                      label: 'Abrir partidas',
                      variant: AfActionVariant.link,
                      onPressed: onYear == null
                          ? null
                          : () => onYear!(root.categoryId),
                    ),
                  ],
                ),
              ),
          ],
        ),
        AfBarChart(
          title: 'Presupuesto por categoría',
          period: '$monthLabel ${data.year}',
          data: [
            for (final root in roots)
              AfBarDatum(
                label: root.category.path,
                value: root.months[focusedMonth - 1].total.hasBudget
                    ? AfChartValue.euros(
                        root.months[focusedMonth - 1].total.amountCents,
                      )
                    : const AfChartValue.unbudgeted(),
                role: AfSeriesRole.budget,
              ),
          ],
        ),
      ],
    );
  }
}
