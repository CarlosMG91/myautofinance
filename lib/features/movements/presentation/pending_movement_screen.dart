import 'package:flutter/material.dart';

import '../domain/category_management.dart';
import '../domain/movement_repository.dart';
import '../domain/pending_movement_repository.dart';
import 'movement_list_controller.dart' show movementEuro;
import 'movement_record_list.dart';
import 'pending_movement_controller.dart';

class PendingMovementScreen extends StatefulWidget {
  const PendingMovementScreen({
    super.key,
    required this.controller,
    required this.selectCategory,
    required this.onOpen,
    required this.onReturn,
    this.onBatch,
    this.navigation,
    this.bottomNavigation,
    this.returnLabel = 'Volver al origen',
  });
  final PendingMovementController controller;
  final Future<CategoryDetails?> Function() selectCategory;
  final Future<void> Function(String id) onOpen;
  final Future<void> Function(String batchId)? onBatch;
  final VoidCallback onReturn;
  final Widget? navigation, bottomNavigation;
  final String returnLabel;

  @override
  State<PendingMovementScreen> createState() => _PendingMovementScreenState();
}

class _PendingMovementScreenState extends State<PendingMovementScreen> {
  final _scroll = ScrollController();
  final _concept = TextEditingController();
  final _from = TextEditingController();
  final _through = TextEditingController();
  final _contentFocus = FocusNode();
  final _rowFocus = <String, FocusNode>{};
  String? _account, _batch, _validation;
  PendingMovementController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _account = c.query.accountId;
    _batch = c.query.batchId;
    _concept.text = c.query.concept;
    _from.text = c.query.from?.value ?? '';
    final until = c.query.until;
    if (until != null) {
      final date = DateTime.parse('${until.value}T00:00:00Z')
          .subtract(const Duration(days: 1));
      _through.text = ValueDate(date.year, date.month, date.day).value;
    }
    c.addListener(_changed);
    c.refresh();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    c.dispose();
    _scroll.dispose();
    _concept.dispose();
    _from.dispose();
    _through.dispose();
    _contentFocus.dispose();
    for (final node in _rowFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _apply() async {
    if (c.locked) return;
    c.filtersEdited();
    try {
      final from = _from.text.trim().isEmpty
          ? null
          : ValueDate.parse(_from.text.trim());
      final through = _through.text.trim().isEmpty
          ? null
          : ValueDate.parse(_through.text.trim());
      if (from != null && through != null && from.compareTo(through) > 0) {
        throw const MovementFailure('Desde no puede ser posterior a hasta.');
      }
      ValueDate? until;
      if (through != null && through.value != '9999-12-31') {
        final next = DateTime.parse('${through.value}T00:00:00Z')
            .add(const Duration(days: 1));
        until = ValueDate(next.year, next.month, next.day);
      }
      final query = PendingMovementQuery(
        from: from,
        until: until,
        accountId: _account,
        batchId: _batch,
        concept: _concept.text,
      );
      setState(() => _validation = null);
      await c.apply(query);
    } on MovementFailure catch (failure) {
      setState(() => _validation = 'Filtros sin aplicar: ${failure.message}');
    }
  }

  Future<void> _clearFilters() async {
    _from.clear();
    _through.clear();
    _concept.clear();
    _account = _batch = null;
    await _apply();
  }

  Future<void> _returnFrom(Future<void> Function() open, {String? id}) async {
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    await open();
    if (!mounted) return;
    // Detalle puede editar elegibilidad: descartar únicamente UUID ya ausentes.
    await c.refresh();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll.hasClients) {
        _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
      }
      (_rowFocus[id] ?? _contentFocus).requestFocus();
    });
  }

  Future<void> _assign({String? id}) async {
    final request = c.beginAssignment(id: id);
    if (request == null) return;
    final trigger = FocusManager.instance.primaryFocus;
    try {
      final category = await widget.selectCategory();
      if (!mounted) return;
      if (category == null) {
        c.cancelAssignment();
        return;
      }
      final count = request.movements.ids.length;
      final route = DialogRoute<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          insetPadding: const EdgeInsets.all(16),
          title: Text(
            'Confirmar asignación · $count ${count == 1 ? 'movimiento' : 'movimientos'}',
          ),
          content: Text(
            'Categoría destino: ${category.path}\n\n'
            'Únicamente estos UUID: ${request.movements.ids.join(', ')}.\n\n'
            'Se comprobará que todos siguen importados y sin categoría y que el destino sigue activo. '
            'Si alguno cambió, se rechazará el lote completo.',
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Guardar categoría'),
            ),
          ],
        ),
      );
      final confirmed = await Navigator.of(context).push(route) ?? false;
      await route.completed;
      if (!mounted) return;
      if (!confirmed) {
        c.cancelAssignment();
        return;
      }
      final success = await c.assign(request, category.node.id);
      if (mounted && success) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _contentFocus.requestFocus();
        });
      }
    } catch (failure) {
      c.rejectAssignment(failure);
    } finally {
      if (mounted && !c.sending && trigger?.context != null) {
        trigger?.requestFocus();
      }
    }
  }

  double get _controlWidth =>
      MediaQuery.sizeOf(context).width < 600 ? double.infinity : 260;
  Widget _field(TextEditingController controller, String label) => SizedBox(
    width: _controlWidth,
    child: TextField(
      controller: controller,
      enabled: !c.locked,
      onChanged: (_) => c.filtersEdited(),
      onSubmitted: (_) => _apply(),
      decoration: InputDecoration(labelText: label),
    ),
  );

  Widget _dropdown(
    String label,
    String? value,
    Map<String, String> labels,
    ValueChanged<String?> change,
  ) => SizedBox(
    width: _controlWidth,
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label-$value-${labels.keys.join()}'),
      initialValue: value ?? '',
      isExpanded: true,
      isDense: false,
      itemHeight: null,
      decoration: InputDecoration(labelText: label),
      selectedItemBuilder: (_) => [
        Text(
          label == 'Lote' ? 'Todos los lotes' : 'Todas las cuentas',
          maxLines: 1,
        ),
        if (value != null && !labels.containsKey(value))
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
        for (final entry in labels.entries)
          Tooltip(
            message: '${entry.value} · ${entry.key}',
            child: Text(
              '${entry.value} · ${entry.key}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      items: [
        DropdownMenuItem(
          value: '',
          child: Text(
            label == 'Lote' ? 'Todos los lotes' : 'Todas las cuentas',
          ),
        ),
        if (value != null && !labels.containsKey(value))
          DropdownMenuItem(value: value, child: Text(value)),
        for (final entry in labels.entries)
          DropdownMenuItem(
            value: entry.key,
            child: Text('${entry.value} · ${entry.key}'),
          ),
      ],
      onChanged: c.locked
          ? null
          : (v) {
              change(v == '' ? null : v);
              _apply();
            },
    ),
  );

  Widget _check(MovementRecord row) => SizedBox(
    width: 48,
    height: 48,
    child: Checkbox(
      semanticLabel: 'Seleccionar ${row.data.concept} · ${row.id}',
      value: c.selected.contains(row.id),
      onChanged: !c.canAssign ? null : (v) => c.toggle(row.id, v!),
    ),
  );

  Widget _actions(MovementRecord row) => Wrap(
    children: [
      TextButton(
        focusNode: _rowFocus.putIfAbsent(row.id, () => FocusNode()),
        onPressed: c.locked || !c.filtersValid || c.requiresRefresh
            ? null
            : () => _assign(id: row.id),
        child: Text('Categorizar ${row.data.concept}'),
      ),
      TextButton(
        focusNode: _rowFocus.putIfAbsent('open-${row.id}', () => FocusNode()),
        onPressed: c.locked
            ? null
            : () => _returnFrom(
                () => widget.onOpen(row.id),
                id: 'open-${row.id}',
              ),
        child: Text('Abrir ${row.data.concept}'),
      ),
      if (widget.onBatch != null && row.batchId != null)
        TextButton(
          focusNode: _rowFocus.putIfAbsent(
            'batch-${row.id}',
            () => FocusNode(),
          ),
          onPressed: c.locked
              ? null
              : () => _returnFrom(
                  () => widget.onBatch!(row.batchId!),
                  id: 'batch-${row.id}',
                ),
          child: const Text('Ver lote'),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final wide =
        MediaQuery.sizeOf(context).width >= 840 &&
        MediaQuery.textScalerOf(context).scale(14) < 21;
    final page = c.page;
    final filtered =
        c.query.from != null ||
        c.query.until != null ||
        c.query.batchId != null ||
        c.query.accountId != null ||
        c.query.concept.trim().isNotEmpty;
    Widget guarded(Widget child) => ExcludeFocus(
      excluding: c.operationActive,
      child: IgnorePointer(ignoring: c.operationActive, child: child),
    );
    final content = SafeArea(
      child: SingleChildScrollView(
        controller: _scroll,
        padding: EdgeInsets.all(wide ? 24 : 16),
        child: Focus(
          focusNode: _contentFocus,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Importados sin categoría · todos los periodos por defecto',
              ),
              const Text('Recientes primero · fecha de valor'),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _dropdown('Lote', _batch, c.batches, (v) => _batch = v),
                  _dropdown(
                    'Cuenta',
                    _account,
                    c.accounts,
                    (v) => _account = v,
                  ),
                  _field(_from, 'Desde · AAAA-MM-DD'),
                  _field(_through, 'Hasta incluido · AAAA-MM-DD'),
                  _field(_concept, 'Buscar por concepto'),
                  FilledButton(
                    onPressed: c.locked ? null : _apply,
                    child: const Text('Aplicar filtros'),
                  ),
                  TextButton(
                    onPressed: c.locked ? null : _clearFilters,
                    child: const Text('Limpiar filtros'),
                  ),
                ],
              ),
              const Text(
                'Fechas incluidas. Sin fechas: todos los periodos. Cambiar filtros limpia la selección.',
              ),
              if (_validation != null)
                Semantics(liveRegion: true, child: Text(_validation!)),
              if (c.notice != null)
                Semantics(liveRegion: true, child: Text(c.notice!)),
              if (c.loading)
                Semantics(
                  liveRegion: true,
                  child: Text('Cargando pendientes…'),
                ),
              if (c.operationActive)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    c.sending
                        ? 'Guardando categoría…'
                        : 'Revisando asignación…',
                  ),
                ),
              if (c.error != null)
                Semantics(liveRegion: true, child: Text(c.error!)),
              if (c.error != null || c.requiresRefresh)
                FilledButton(
                  onPressed: c.locked
                      ? null
                      : c.requiresRefresh
                      ? c.update
                      : () => c.refresh(),
                  child: Text(
                    c.requiresRefresh
                        ? 'Actualizar pendientes'
                        : 'Reintentar lectura',
                  ),
                ),
              if (page != null) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    'Total pendiente del ámbito filtrado: ${page.totalCount} movimientos',
                  ),
                ),
                Text(
                  'Página ${c.pageIndex + 1} de ${(page.totalCount / c.pageSize).ceil().clamp(1, 999999999)} · ${page.records.length} visibles',
                ),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    '${c.selected.length} seleccionados · UUID explícitos: ${c.selected.join(', ')}',
                  ),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: !c.canAssign || page.records.isEmpty
                          ? null
                          : c.selectPage,
                      child: Text(
                        'Seleccionar página visible (${page.records.length})',
                      ),
                    ),
                    TextButton(
                      onPressed: c.locked ? null : c.clearSelection,
                      child: const Text('Limpiar selección'),
                    ),
                    FilledButton(
                      onPressed: !c.canAssign || c.selected.isEmpty
                          ? null
                          : () => _assign(),
                      child: Text('Asignar categoría (${c.selected.length})'),
                    ),
                  ],
                ),
                if (page.records.isEmpty)
                  Text(
                    filtered
                        ? 'No hay pendientes con estos filtros. Limpia los filtros para revisar otros periodos o lotes.'
                        : 'No quedan importados pendientes. Los movimientos manuales se gestionan en Movimientos.',
                  ),
                if (page.records.isNotEmpty)
                  MovementRecordList(
                    actionLabel: 'Acción',
                    records: page.records,
                    wide: wide,
                    labels: const [
                      'Fecha de valor',
                      'Concepto',
                      'Cuenta',
                      'Procedencia',
                      'Importe EUR',
                    ],
                    values: (row) => [
                      row.data.valueDate.value,
                      '${row.data.concept}\n${row.id}',
                      c.accounts[row.data.accountId] ?? row.data.accountId,
                      '${c.batches[row.batchId] ?? row.batchId}\nFila ${row.sourceOrdinal}',
                      movementEuro(row.data.amountCents),
                    ],
                    checkbox: _check,
                    actions: _actions,
                  ),
                Wrap(
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: !c.canAssign || c.pageIndex == 0
                          ? null
                          : c.previous,
                      child: const Text('Página anterior'),
                    ),
                    TextButton(
                      onPressed: !c.canAssign || page.nextCursor == null
                          ? null
                          : c.next,
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
    return PopScope(
      canPop: !c.operationActive,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bandeja de categorización'),
          leading: IconButton(
            tooltip: widget.returnLabel,
            onPressed: c.operationActive ? null : widget.onReturn,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        bottomNavigationBar: widget.bottomNavigation == null
            ? null
            : guarded(widget.bottomNavigation!),
        body: widget.navigation == null
            ? content
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  guarded(widget.navigation!),
                  Expanded(child: content),
                ],
              ),
      ),
    );
  }
}
