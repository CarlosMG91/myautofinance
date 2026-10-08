import 'package:flutter/material.dart';

import '../domain/movement_repository.dart';

/// Tabla compacta y tarjetas EP-010, compartidas por Movimientos y pendientes.
class MovementRecordList extends StatelessWidget {
  const MovementRecordList({
    super.key,
    required this.records,
    required this.labels,
    required this.values,
    required this.checkbox,
    required this.actions,
    required this.wide,
    this.actionLabel = 'Detalle',
  });
  final List<MovementRecord> records;
  final List<String> labels;
  final List<String> Function(MovementRecord) values;
  final Widget Function(MovementRecord) checkbox, actions;
  final bool wide;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    if (wide) {
      return Table(
        columnWidths: {
          0: const FixedColumnWidth(48),
          for (var i = 0; i < labels.length; i++)
            i + 1: FlexColumnWidth([1.0, 2.0, 1.5, 2.0, 1.2][i]),
          labels.length + 1: const FlexColumnWidth(1.5),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [
              for (final title in ['', ...labels, actionLabel])
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
          for (final row in records)
            TableRow(
              children: [
                checkbox(row),
                for (final value in values(row))
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(value, style: const TextStyle(fontSize: 14)),
                  ),
                actions(row),
              ],
            ),
        ],
      );
    }
    return Column(
      children: [
        for (final row in records)
          Card(
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    checkbox(row),
                    for (final (index, value) in values(row).indexed)
                      Text('${labels[index]}: $value'),
                    actions(row),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
