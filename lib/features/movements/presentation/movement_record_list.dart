import 'package:flutter/material.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

import '../domain/movement_repository.dart';

/// Actividad compartida. No agrupa ni deduplica registros por sus etiquetas.
/// Consultas, selección, callbacks y scroll pertenecen al consumidor.
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

  /// Fecha, concepto, cuenta, categoría/procedencia e importe, en ese orden.
  final List<String> labels;
  final List<String> Function(MovementRecord) values;
  final Widget Function(MovementRecord) checkbox, actions;
  final bool wide;
  final String actionLabel;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AfTokens.surface,
      borderRadius: BorderRadius.circular(AfTokens.cardRadius),
      border: Border.all(color: AfTokens.border),
    ),
    child: Column(
      children: [
        for (final record in records)
          MovementActivityRow(
            key: ValueKey(record.id),
            record: record,
            accountLabel: values(record)[2],
            categoryLabel: values(record)[3],
            categoryCaption: labels[3],
            selection: checkbox(record),
            actions: actions(record),
            wide: wide,
          ),
      ],
    ),
  );
}

/// Fila pública para EP-024. No introduce filtros, agregaciones ni navegación.
class MovementActivityRow extends StatelessWidget {
  const MovementActivityRow({
    super.key,
    required this.record,
    required this.accountLabel,
    required this.categoryLabel,
    required this.selection,
    required this.actions,
    required this.wide,
    this.categoryCaption = 'Categoría',
  });
  final MovementRecord record;
  final String accountLabel, categoryLabel, categoryCaption;
  final Widget selection, actions;
  final bool wide;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final horizontal =
          wide &&
          constraints.maxWidth >= 600 &&
          !AfTokens.reflow(context, constraints.maxWidth);
      final description = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(
            record.data.concept,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            '${record.data.valueDate.value} · fecha de valor · $accountLabel',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AfTokens.muted),
          ),
          Text('$categoryCaption: $categoryLabel'),
        ],
      );
      final amount = Column(
        crossAxisAlignment: horizontal
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        spacing: 4,
        children: [
          AfMoneyText(AfAmount(record.data.amountCents)),
          Text(
            record.data.amountCents < 0 ? 'Salida' : 'Entrada',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AfTokens.muted),
          ),
        ],
      );
      return Semantics(
        container: true,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AfTokens.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  selection,
                  Expanded(
                    child: horizontal
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 24,
                            children: [
                              Expanded(child: description),
                              amount,
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 12,
                            children: [description, amount],
                          ),
                  ),
                ],
              ),
              Padding(
                padding: EdgeInsets.only(left: horizontal ? 60 : 0),
                child: actions,
              ),
            ],
          ),
        ),
      );
    },
  );
}
