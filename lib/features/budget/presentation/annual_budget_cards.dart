import 'package:flutter/material.dart';

import '../domain/annual_budget_query.dart';

/// Presentación táctil de la misma consulta anual, sin escrituras propias.
class AnnualBudgetCards extends StatelessWidget {
  const AnnualBudgetCards({
    super.key,
    required this.rows,
    required this.months,
    required this.focusedMonth,
    required this.expandedMonths,
    required this.onExpandMonths,
    required this.category,
    required this.cell,
    required this.total,
    required this.monthTotal,
  });

  final List<AnnualBudgetRow> rows;
  final List<String> months;
  final int focusedMonth;
  final Set<String> expandedMonths;
  final void Function(String id, bool expanded) onExpandMonths;
  final Widget Function(AnnualBudgetRow row) category;
  final Widget Function(AnnualBudgetRow row, int month, bool focused) cell;
  final Widget Function(AnnualBudgetRow row) total;
  final Widget Function(int month) monthTotal;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final row in rows)
        Card(
          key: ValueKey('annual-card-${row.categoryId}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                category(row),
                if (row.category.node.depth > 1) Text(row.category.path),
                const Text('Total anual · Solo lectura'),
                total(row),
                Text('${months[focusedMonth - 1]} · Mes enfocado'),
                cell(row, focusedMonth, true),
                ExpansionTile(
                  key: ValueKey('annual-months-${row.categoryId}'),
                  title: const Text('Los doce meses'),
                  initiallyExpanded: expandedMonths.contains(row.categoryId),
                  onExpansionChanged: (expanded) =>
                      onExpandMonths(row.categoryId, expanded),
                  maintainState: true,
                  tilePadding: EdgeInsets.zero,
                  children: [
                    for (var month = 1; month <= 12; month++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '${months[month - 1]}${month == focusedMonth ? ' · Enfocado' : ''}',
                            ),
                            cell(row, month, false),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Total mensual · solo raíces · Solo lectura'),
              for (var month = 1; month <= 12; month++) ...[
                Text(months[month - 1]),
                monthTotal(month),
              ],
            ],
          ),
        ),
      ),
    ],
  );
}
