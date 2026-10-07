import 'package:flutter/material.dart';

import '../importing.dart';
import '../../movements/movements.dart';

String importMoney(Object cents) {
  final value = cents is BigInt ? cents : BigInt.from(cents as int);
  final digits = (value.abs() ~/ BigInt.from(100)).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  return '${value.isNegative
      ? '−'
      : value > BigInt.zero
      ? '+'
      : ''}$digits,${(value.abs() % BigInt.from(100)).toString().padLeft(2, '0')} €';
}

String importCategoryPath(String id, List<CategoryNode> nodes) {
  final parts = <String>[];
  String? current = id;
  final seen = <String>{};
  while (current != null && seen.add(current)) {
    final matches = nodes.where((n) => n.id == current);
    if (matches.isEmpty) {
      parts.insert(0, current);
      break;
    }
    final node = matches.first;
    parts.insert(0, node.name);
    current = node.parentId;
  }
  return parts.join(' / ');
}

String importSourceLabel(ImportSource source) => switch (source) {
  ImportSource.historicalCsv => 'CSV histórico',
  ImportSource.bankXls => 'XLS bancario',
};

String importPlannedCategoryPath(
  ImportCategoryReference reference,
  ImportReferenceBindings bindings,
  List<CategoryNode> nodes,
) {
  final seen = <ImportCategoryReference>{};
  String path(ImportCategoryTarget target) {
    if (target.existingId != null) {
      return importCategoryPath(target.existingId!, nodes);
    }
    final ref = target.proposedReference!;
    if (!seen.add(ref)) return 'Plan inválido';
    final plan = bindings.newCategories[ref];
    if (plan == null) return 'Padre pendiente';
    return plan.parent == null
        ? plan.name
        : '${path(plan.parent!)} / ${plan.name}';
  }

  return path(ImportCategoryTarget.proposed(reference));
}

/// Tabla compacta con desplazamiento horizontal; texto ampliado usa tarjetas.
class ImportRowsView extends StatelessWidget {
  const ImportRowsView({
    super.key,
    required this.rows,
    this.accountLabel,
    this.categoryLabel,
    this.onOriginal,
    this.statusLabel,
  });
  final List<InterpretedImportRow> rows;
  final String Function(InterpretedMovement)? accountLabel;
  final String Function(ImportCategoryReference)? categoryLabel;
  final void Function(InterpretedImportRow)? onOriginal;
  final String Function(InterpretedImportRow)? statusLabel;

  List<String> values(InterpretedImportRow row) {
    final ref = switch (row) {
      InterpretedMovement() => row.category,
      InterpretedBudget() => row.category,
    };
    return [
      '${row.sourceOrdinal}',
      row is InterpretedMovement ? 'REAL' : 'PRESUPUESTO',
      switch (row) {
        InterpretedMovement() => row.valueDate.value,
        InterpretedBudget() => row.month.value.substring(0, 7),
      },
      row.concept,
      importMoney(row.amount.originalCents),
      importMoney(row.amount.internalCents),
      ref == null
          ? 'Sin clasificar'
          : categoryLabel?.call(ref) ?? ref.path.join(' / '),
      row is InterpretedMovement
          ? accountLabel?.call(row) ?? row.account.name ?? 'Cuenta pendiente'
          : 'No aplica',
      if (statusLabel != null) statusLabel!(row),
    ];
  }

  List<String> get labels => [
    'Fila',
    'Tipo',
    'Fecha / mes',
    'Concepto',
    'Original',
    'Interno',
    'Categoría',
    'Cuenta',
    if (statusLabel != null) 'Estado',
  ];
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= 840 &&
          MediaQuery.textScalerOf(context).scale(16) < 24) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 20,
            dataRowMinHeight: 56,
            dataRowMaxHeight: 80,
            columns: [
              for (final label in labels) DataColumn(label: Text(label)),
              const DataColumn(label: Text('Origen')),
            ],
            rows: [
              for (final row in rows)
                DataRow(
                  cells: [
                    for (final value in values(row))
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: Text(
                            value,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    DataCell(
                      TextButton(
                        onPressed: onOriginal == null
                            ? null
                            : () => onOriginal!(row),
                        child: Text('Originales ${row.sourceOrdinal}'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      }
      return Column(
        children: [
          for (final row in rows)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final entry in values(row).asMap().entries)
                      Text('${labels[entry.key]}: ${entry.value}'),
                    if (onOriginal != null)
                      TextButton(
                        onPressed: () => onOriginal!(row),
                        child: Text('Originales ${row.sourceOrdinal}'),
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

Future<void> showImportOriginal(
  BuildContext context,
  InterpretedImportRow row,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text('Campos originales · fila ${row.sourceOrdinal}'),
    content: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Concepto: ${row.concept}'),
          Text('Discrecionalidad: ${row.discretion ?? 'Sin dato'}'),
          Text('Original: ${importMoney(row.amount.originalCents)}'),
          Text('Interno: ${importMoney(row.amount.internalCents)}'),
          for (final field in row.originalFields)
            SelectableText('${field.name}: ${field.value}'),
          if (row.originalFields.isEmpty) const Text('Sin campos adicionales.'),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cerrar'),
      ),
    ],
  ),
);
