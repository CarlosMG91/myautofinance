import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../importing.dart';
import 'import_controller.dart';
import 'import_widgets.dart';
import 'import_layout.dart';
import '../../../ui/autofinance_ui.dart';

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

  String _confirmedAt(ImportBatch batch) {
    final instant = DateTime.tryParse(batch.importedAt);
    return instant == null
        ? batch.importedAt
        : DateFormat('dd/MM/yyyy · HH:mm', 'es_ES').format(instant.toLocal());
  }

  Widget _metadata(ImportBatch batch) => ImportSection(
    title: 'Lote confirmado',
    children: [
      Text(batch.originalName, style: Theme.of(context).textTheme.titleLarge),
      Text('Confirmado: ${_confirmedAt(batch)}'),
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
      const SizedBox(height: 16),
      Text('Original', style: Theme.of(context).textTheme.titleLarge),
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
      const SizedBox(height: 24),
      Text('Registro actual', style: Theme.of(context).textTheme.titleLarge),
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
    body: SafeArea(
      child: SingleChildScrollView(
        child: AfPageLayout(
          page: AfPageSlots(
            title: widget.rowId != null
                ? 'Procedencia de fila'
                : widget.batchId != null
                ? 'Detalle del lote'
                : 'Historial de importaciones',
            contextTrail: const Text(
              'Gestión / Importaciones · identidad por contenido',
            ),
            actions: [
              AfAction(
                label: 'Volver',
                icon: AfIcons.back,
                variant: AfActionVariant.link,
                onPressed: widget.onReturn,
              ),
              AfAction(
                label: 'Recargar contexto',
                onPressed: _busy ? null : () => _load(reset: true),
              ),
            ],
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 24,
              children: [
                if (_busy)
                  const AfStatus(
                    kind: AfStatusKind.loading,
                    message: 'Consultando SQLite…',
                  ),
                if (_error != null)
                  AfStatus(
                    kind: AfStatusKind.error,
                    message: _error!,
                    action: AfAction(
                      label: 'Reintentar',
                      onPressed: _busy ? null : _load,
                    ),
                  ),
                if (!_busy && _error == null) ...[
                  if (widget.rowId != null)
                    _row == null
                        ? const AfStatus(
                            kind: AfStatusKind.empty,
                            message: 'Origen no encontrado.',
                          )
                        : AfCard(child: _rowDetail(_row!)),
                  if (widget.batchId != null) ...[
                    if (_batch == null)
                      const AfStatus(
                        kind: AfStatusKind.empty,
                        message: 'Lote no encontrado.',
                      )
                    else
                      _metadata(_batch!),
                    ImportSection(
                      title: 'Filas del lote',
                      children: [
                        const Text(
                          'La procedencia conserva el original. El registro actual puede estar corregido o borrado.',
                        ),
                        for (final row in _rows)
                          AfValueRow(
                            label:
                                'Fila ${row.sourceOrdinal} · ${row.kind == ImportRecordKind.movement ? 'REAL' : 'PRESUPUESTO'}',
                            contextLabel: row.isDeleted
                                ? 'Registro borrado'
                                : 'Registro actual disponible',
                            value: Text('Ver origen ${row.sourceOrdinal}'),
                            onPressed: () => widget.onRow(row.id),
                          ),
                      ],
                    ),
                  ],
                  if (widget.batchId == null && widget.rowId == null) ...[
                    const Text(
                      'Solo lotes confirmados. No se conservan archivos completos ni intentos fallidos o cancelados.',
                    ),
                    if (_batches.isEmpty)
                      const AfStatus(
                        kind: AfStatusKind.empty,
                        message: 'Sin lotes confirmados.',
                      )
                    else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth >= 840 &&
                              !AfTokens.reflow(context, constraints.maxWidth)) {
                            return AfCard(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  dataRowMinHeight: 64,
                                  dataRowMaxHeight: double.infinity,
                                  columns: const [
                                    DataColumn(label: Text('Archivo / origen')),
                                    DataColumn(label: Text('Confirmado')),
                                    DataColumn(
                                      label: Text('REAL'),
                                      numeric: true,
                                    ),
                                    DataColumn(
                                      label: Text('PRESUPUESTO'),
                                      numeric: true,
                                    ),
                                    DataColumn(label: Text('Detalle')),
                                  ],
                                  rows: [
                                    for (final batch in _batches)
                                      DataRow(
                                        cells: [
                                          DataCell(
                                            SizedBox(
                                              width: 260,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(batch.originalName),
                                                  Text(
                                                    importSourceLabel(
                                                      batch.source,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          DataCell(Text(_confirmedAt(batch))),
                                          DataCell(
                                            AfNumericText(
                                              '${batch.movementCount}',
                                            ),
                                          ),
                                          DataCell(
                                            AfNumericText(
                                              '${batch.budgetCount}',
                                            ),
                                          ),
                                          DataCell(
                                            TextButton(
                                              onPressed: () =>
                                                  widget.onBatch(batch.id),
                                              child: const Text(
                                                'Ver detalle del lote',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }
                          return Column(
                            spacing: 16,
                            children: [
                              for (final batch in _batches)
                                ImportSection(
                                  title: batch.originalName,
                                  children: [
                                    Text('Confirmado: ${_confirmedAt(batch)}'),
                                    Text(
                                      'Origen: ${importSourceLabel(batch.source)}',
                                    ),
                                    Text(
                                      'REAL: ${batch.movementCount} · PRESUPUESTO: ${batch.budgetCount}',
                                    ),
                                    AfAction(
                                      label: 'Ver detalle del lote',
                                      variant: AfActionVariant.link,
                                      onPressed: () => widget.onBatch(batch.id),
                                    ),
                                  ],
                                ),
                            ],
                          );
                        },
                      ),
                  ],
                  if (widget.rowId == null)
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        AfAction(
                          label: 'Página anterior',
                          variant: AfActionVariant.link,
                          onPressed: _page == 0
                              ? null
                              : () {
                                  _page--;
                                  _load();
                                },
                        ),
                        Text('Página ${_page + 1}'),
                        AfAction(
                          label: 'Página siguiente',
                          variant: AfActionVariant.link,
                          onPressed:
                              (widget.batchId != null
                                  ? _nextRow != null
                                  : _nextBatch != null)
                              ? _next
                              : null,
                        ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
