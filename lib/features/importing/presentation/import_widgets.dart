import 'package:flutter/material.dart';

import '../importing.dart';
import '../../movements/movements.dart';

/// Relee los pendientes actuales sin alterar los conteos originales del lote.
class ImportPendingLink extends StatefulWidget {
  const ImportPendingLink({
    super.key,
    required this.batchId,
    required this.open,
    required this.count,
    this.onReturned,
  });
  final String batchId;
  final Future<void> Function(String) open;
  final Future<int> Function(String) count;
  final Future<void> Function()? onReturned;
  @override
  State<ImportPendingLink> createState() => _ImportPendingLinkState();
}

class _ImportPendingLinkState extends State<ImportPendingLink> {
  late Future<int> _count;
  final _focus = FocusNode();
  @override
  void initState() {
    super.initState();
    _count = widget.count(widget.batchId);
  }

  @override
  void didUpdateWidget(ImportPendingLink oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.batchId != widget.batchId) {
      _count = widget.count(widget.batchId);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<int>(
    future: _count,
    builder: (context, snapshot) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (snapshot.connectionState != ConnectionState.done)
          const LinearProgressIndicator(
            semanticsLabel: 'Consultando pendientes',
          ),
        Text(
          snapshot.hasError
              ? 'Pendientes: contador no disponible'
              : snapshot.connectionState == ConnectionState.done
              ? 'Pendientes de categorizar: ${snapshot.data}'
              : 'Consultando pendientes…',
        ),
        TextButton(
          focusNode: _focus,
          onPressed: () async {
            await widget.open(widget.batchId);
            if (!mounted) return;
            setState(() {
              _count = widget.count(widget.batchId);
            });
            _focus.requestFocus();
            await widget.onReturned?.call();
          },
          child: const Text('Revisar pendientes del lote'),
        ),
      ],
    ),
  );
}

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
    this.originalLabel = 'Original',
  });
  final List<InterpretedImportRow> rows;
  final String Function(InterpretedMovement)? accountLabel;
  final String Function(ImportCategoryReference)? categoryLabel;
  final void Function(InterpretedImportRow)? onOriginal;
  final String Function(InterpretedImportRow)? statusLabel;
  final String originalLabel;

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
        InterpretedBudget() => row.month.value,
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
    originalLabel,
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
