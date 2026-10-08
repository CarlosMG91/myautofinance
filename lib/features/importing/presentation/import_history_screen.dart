import 'package:flutter/material.dart';

import '../importing.dart';
import 'import_controller.dart';
import 'import_widgets.dart';

class ImportHistoryScreen extends StatefulWidget {
  const ImportHistoryScreen({
    super.key,
    required this.load,
    required this.onReturn,
    required this.onBatch,
    this.onPending,
    this.pendingCount,
    required this.onRow,
    required this.onRecord,
    this.batchId,
    this.rowId,
  });
  final ImportServicesLoader load;
  final VoidCallback onReturn;
  final void Function(String) onBatch, onRow;
  final Future<void> Function(ImportRowHistory) onRecord;
  final String? batchId, rowId;
  final Future<void> Function(String)? onPending;
  final Future<int> Function(String)? pendingCount;
  @override
  State<ImportHistoryScreen> createState() => _ImportHistoryScreenState();
}

class _ImportHistoryScreenState extends State<ImportHistoryScreen> {
  bool _busy = true;
  String? _error;
  ImportBatch? _batch;
  ImportRowHistory? _row;
  List<ImportBatch> _batches = [];
  List<ImportRowHistory> _rows = [];
  final _batchCursors = <ImportBatchCursor?>[null];
  final _rowCursors = <ImportRowCursor?>[null];
  ImportBatchCursor? _nextBatch;
  ImportRowCursor? _nextRow;
  int _page = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = false, bool silent = false}) async {
    if (reset) {
      _page = 0;
      _batchCursors
        ..clear()
        ..add(null);
      _rowCursors
        ..clear()
        ..add(null);
    }
    setState(() {
      if (!silent) _busy = true;
      _error = null;
    });
    try {
      final history = (await widget.load()).history;
      if (widget.rowId != null) {
        _row = await history.getRow(widget.rowId!);
      } else if (widget.batchId != null) {
        _batch = await history.getBatch(widget.batchId!);
        final page = await history.listRows(
          widget.batchId!,
          limit: 50,
          cursor: _rowCursors[_page],
        );
        _rows = page.items;
        _nextRow = page.next;
      } else {
        final page = await history.listBatches(
          limit: 50,
          cursor: _batchCursors[_page],
        );
        _batches = page.items;
        _nextBatch = page.next;
      }
    } catch (_) {
      _error = 'No se pudo consultar el historial. Puedes reintentar o recargar el contexto.';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _next() async {
    if (_busy) return;
    if (widget.batchId != null) {
      if (_nextRow == null) return;
      if (_rowCursors.length == _page + 1) _rowCursors.add(_nextRow);
    } else {
      if (_nextBatch == null) return;
      if (_batchCursors.length == _page + 1) _batchCursors.add(_nextBatch);
    }
    _page++;
    await _load();
  }

  Widget _metadata(ImportBatch batch) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(batch.originalName, style: Theme.of(context).textTheme.titleLarge),
      Text('Confirmado: ${batch.importedAt}'),
      Text('Origen: ${importSourceLabel(batch.source)}'),
      Text(
        'Contrato: ${batch.contractVersion} · lector: ${batch.formatVersion ?? 'No disponible'}',
      ),
      SelectableText('SHA-256: ${batch.sha256}'),
      SelectableText('Lote: ${batch.id}'),
      if (widget.onPending != null && widget.pendingCount != null)
        ImportPendingLink(
          batchId: batch.id,
          open: widget.onPending!,
          count: widget.pendingCount!,
          onReturned: () => _load(silent: true),
        ),
      Text('REAL: ${batch.movementCount} · PRESUPUESTO: ${batch.budgetCount}'),
    ],
  );
  Widget _rowDetail(ImportRowHistory row) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Fila ${row.sourceOrdinal} · ${row.kind == ImportRecordKind.movement ? 'REAL' : 'PRESUPUESTO'}',
      ),
      SelectableText('Identidad de origen: ${row.id}'),
      TextButton(
        onPressed: () => widget.onBatch(row.batchId),
        child: const Text('Consultar lote'),
      ),
      const Text('Original', style: TextStyle(fontWeight: FontWeight.bold)),
      if (row.original == null)
        const Text('Original no disponible')
      else ...[
        ImportRowsView(rows: [row.original!]),
        Text(
          'Discrecionalidad original: ${row.original!.discretion ?? 'Sin dato'}',
        ),
        for (final field in row.original!.originalFields)
          SelectableText('${field.name}: ${field.value}'),
        if (row.original!.originalFields.isEmpty)
          const Text('Sin campos adicionales.'),
      ],
      const Text(
        'Registro actual',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      if (row.isDeleted)
        const Text(
          'Registro borrado. Se conserva su procedencia; reimportar no lo recrea.',
        ),
      if (row.currentMovement case final movement?) ...[
        Text(
          '${movement.data.valueDate.value} · ${movement.data.concept} · ${importMoney(movement.data.amountCents)}',
        ),
        Text(
          'Cuenta: ${movement.data.accountId} · categoría: ${movement.data.categoryId ?? 'Sin clasificar'}',
        ),
        Text('Discrecionalidad: ${movement.data.discretion ?? 'Sin dato'}'),
      ],
      if (row.currentBudget case final budget?) ...[
        Text(
          '${budget.data.month.value.substring(0, 7)} · ${budget.data.concept ?? 'Sin dato'} · ${importMoney(budget.data.amountCents)}',
        ),
        Text('Categoría: ${budget.data.categoryId}'),
        Text('Discrecionalidad: ${budget.data.discretion ?? 'Sin dato'}'),
      ],
      if (!row.isDeleted)
        TextButton(
          onPressed: () async {
            await widget.onRecord(row);
            if (mounted) await _load();
          },
          child: const Text('Abrir registro actual'),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      title: Text(
        widget.rowId != null
            ? 'Procedencia de fila'
            : widget.batchId != null
            ? 'Detalle del lote'
            : 'Historial de importaciones',
      ),
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  onPressed: widget.onReturn,
                  child: const Text('Volver'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _load(reset: true),
                  child: const Text('Recargar contexto'),
                ),
              ],
            ),
            if (_busy)
              Semantics(
                liveRegion: true,
                child: const Text('Consultando SQLite…'),
              ),
            if (_error != null) ...[
              Semantics(liveRegion: true, child: Text(_error!)),
              TextButton(
                onPressed: _busy ? null : _load,
                child: const Text('Reintentar'),
              ),
            ],
            if (!_busy && _error == null) ...[
              if (widget.rowId != null)
                _row == null
                    ? const Text('Origen no encontrado.')
                    : _rowDetail(_row!),
              if (widget.batchId != null) ...[
                if (_batch == null)
                  const Text('Lote no encontrado.')
                else
                  _metadata(_batch!),
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 840 &&
                        MediaQuery.textScalerOf(context).scale(16) < 24) {
                      return DataTable(
                        columns: const [
                          DataColumn(label: Text('Fila')),
                          DataColumn(label: Text('Tipo')),
                          DataColumn(label: Text('Estado actual')),
                          DataColumn(label: Text('Origen')),
                        ],
                        rows: [
                          for (final row in _rows)
                            DataRow(
                              cells: [
                                DataCell(Text('${row.sourceOrdinal}')),
                                DataCell(
                                  Text(
                                    row.kind == ImportRecordKind.movement
                                        ? 'REAL'
                                        : 'PRESUPUESTO',
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    row.isDeleted ? 'Borrado' : 'Disponible',
                                  ),
                                ),
                                DataCell(
                                  TextButton(
                                    onPressed: () => widget.onRow(row.id),
                                    child: Text(
                                      'Ver origen ${row.sourceOrdinal}',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        for (final row in _rows)
                          Card(
                            child: ListTile(
                              title: Text(
                                'Fila ${row.sourceOrdinal} · ${row.kind == ImportRecordKind.movement ? 'REAL' : 'PRESUPUESTO'}',
                              ),
                              subtitle: Text(
                                row.isDeleted
                                    ? 'Registro borrado'
                                    : 'Registro actual disponible',
                              ),
                              onTap: () => widget.onRow(row.id),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
              if (widget.batchId == null && widget.rowId == null) ...[
                const Text(
                  'Solo lotes confirmados. No se conservan archivos completos ni intentos fallidos o cancelados.',
                ),
                if (_batches.isEmpty) const Text('Sin lotes confirmados.'),
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 840 &&
                        MediaQuery.textScalerOf(context).scale(16) < 24) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: [
                            for (final label in [
                              'Nombre',
                              'Confirmado',
                              'Origen',
                              'Versiones',
                              'SHA-256',
                              'Conteos',
                              'Detalle',
                            ])
                              DataColumn(label: Text(label)),
                          ],
                          rows: [
                            for (final batch in _batches)
                              DataRow(
                                cells: [
                                  DataCell(Text(batch.originalName)),
                                  DataCell(Text(batch.importedAt)),
                                  DataCell(
                                    Text(importSourceLabel(batch.source)),
                                  ),
                                  DataCell(
                                    Text(
                                      '${batch.contractVersion} / ${batch.formatVersion ?? 'No disponible'}',
                                    ),
                                  ),
                                  DataCell(SelectableText(batch.sha256)),
                                  DataCell(
                                    Text(
                                      '${batch.movementCount} REAL / ${batch.budgetCount} PRESUPUESTO',
                                    ),
                                  ),
                                  DataCell(
                                    TextButton(
                                      onPressed: () => widget.onBatch(batch.id),
                                      child: const Text('Ver detalle del lote'),
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
                        for (final batch in _batches)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _metadata(batch),
                                  TextButton(
                                    onPressed: () => widget.onBatch(batch.id),
                                    child: const Text('Ver detalle del lote'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
              if (widget.rowId == null)
                Wrap(
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: _page == 0
                          ? null
                          : () {
                              _page--;
                              _load();
                            },
                      child: const Text('Página anterior'),
                    ),
                    Text('Página ${_page + 1}'),
                    TextButton(
                      onPressed:
                          (widget.batchId != null
                              ? _nextRow != null
                              : _nextBatch != null)
                          ? _next
                          : null,
                      child: const Text('Página siguiente'),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    ),
  );
}
