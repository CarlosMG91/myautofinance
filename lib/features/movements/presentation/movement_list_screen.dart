import 'package:flutter/material.dart';

import '../domain/movement_repository.dart';
import 'movement_list_controller.dart';

class MovementListScreen extends StatefulWidget {
  const MovementListScreen({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onReturn,
    this.onSelection,
    this.onCreate,
    this.navigation,
    this.bottomNavigation,
    this.returnLabel = 'Volver al origen',
  });
  final MovementListController controller;
  final Future<void> Function(String id) onOpen;
  final VoidCallback onReturn;
  final Future<void> Function()? onCreate;

  /// Entrega UUID y contexto exactos a las acciones de MA-TSK-094.
  final void Function(MovementSelection?, MovementListContext)? onSelection;
  final Widget? navigation, bottomNavigation;
  final String returnLabel;
  @override
  State<MovementListScreen> createState() => _MovementListScreenState();
}

class _MovementListScreenState extends State<MovementListScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  final _from = TextEditingController();
  final _until = TextEditingController();
  final _focus = <String, FocusNode>{};
  String? _validation, _accountId, _categoryId;
  late MovementCategoryScope _scope;
  bool _unclassified = false;
  MovementListController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    _accountId = c.accountId;
    _categoryId = c.categoryId;
    _scope = c.scope;
    _unclassified = c.unclassified;
    _search.text = c.concept;
    _from.text = c.from.value;
    _until.text = c.until?.value ?? '';
    c.addListener(_changed);
    c.refresh();
  }

  void _changed() {
    widget.onSelection?.call(c.selection, c.context);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    c.dispose();
    _scroll.dispose();
    _search.dispose();
    _from.dispose();
    _until.dispose();
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _apply() async {
    try {
      final from = ValueDate.parse(_from.text.trim());
      final until = _until.text.trim().isEmpty
          ? null
          : ValueDate.parse(_until.text.trim());
      if (until != null && from.compareTo(until) >= 0) {
        throw const MovementFailure('Desde debe ser anterior a Hasta.');
      }
      if (until == null && !from.value.startsWith('9999-')) {
        throw const MovementFailure(
          'Hasta es obligatorio salvo en el último año del calendario.',
        );
      }
      c.accountId = _accountId;
      c.categoryId = _categoryId;
      c.scope = _scope;
      c.unclassified = _unclassified;
      c.from = from;
      c.until = until;
      c.concept = _search.text;
      setState(() => _validation = null);
      if (_scroll.hasClients) _scroll.jumpTo(0);
      await c.apply();
    } on MovementFailure catch (e) {
      setState(() => _validation = 'Filtros sin aplicar: ${e.message}');
    }
  }

  Future<void> _open(String id) async {
    final offset = _scroll.offset;
    await widget.onOpen(id);
    if (!mounted) return;
    await c.refresh();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll.hasClients) {
        _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
      }
      _focus[id]?.requestFocus();
    });
  }

  double get _controlWidth =>
      MediaQuery.sizeOf(context).width < 600 ? double.infinity : 260;

  Widget _field(TextEditingController controller, String label) => SizedBox(
    width: _controlWidth,
    child: TextField(
      controller: controller,
      onSubmitted: (_) => _apply(),
      decoration: InputDecoration(labelText: label),
    ),
  );
  Widget _filters() => Wrap(
    spacing: 12,
    runSpacing: 12,
    children: [
      _field(_from, 'Desde · AAAA-MM-DD'),
      _field(_until, 'Hasta exclusivo · AAAA-MM-DD'),
      _field(_search, 'Buscar por concepto'),
      SizedBox(
        width: _controlWidth,
        child: DropdownButtonFormField<String>(
          key: ValueKey('account-$_accountId-${c.accounts}'),
          initialValue: _accountId ?? '',
          isExpanded: true,
          itemHeight: null,
          isDense: false,
          decoration: const InputDecoration(labelText: 'Cuenta'),
          items: [
            const DropdownMenuItem(value: '', child: Text('Todas las cuentas')),
            if (_accountId != null && !c.accounts.containsKey(_accountId))
              DropdownMenuItem(value: _accountId, child: Text(_accountId!)),
            for (final entry in c.accounts.entries)
              DropdownMenuItem(
                value: entry.key,
                child: Text('${entry.value} · ${entry.key.substring(0, 8)}'),
              ),
          ],
          onChanged: c.loading
              ? null
              : (v) {
                  _accountId = v == '' ? null : v;
                  _apply();
                },
        ),
      ),
      SizedBox(
        width: _controlWidth,
        child: DropdownButtonFormField<String>(
          key: ValueKey('category-$_categoryId-$_unclassified-${c.paths}'),
          initialValue: _unclassified ? 'unclassified' : _categoryId ?? '',
          isExpanded: true,
          itemHeight: null,
          isDense: false,
          decoration: const InputDecoration(labelText: 'Categoría'),
          items: [
            const DropdownMenuItem(
              value: '',
              child: Text('Todas las categorías'),
            ),
            const DropdownMenuItem(
              value: 'unclassified',
              child: Text('Sin clasificar'),
            ),
            if (_categoryId != null && !c.paths.containsKey(_categoryId))
              DropdownMenuItem(value: _categoryId, child: Text(_categoryId!)),
            for (final entry in c.paths.entries)
              DropdownMenuItem(
                value: entry.key,
                child: Text('${entry.value} · ${entry.key.substring(0, 8)}'),
              ),
          ],
          onChanged: c.loading
              ? null
              : (v) {
                  _unclassified = v == 'unclassified';
                  _categoryId = v == '' || _unclassified ? null : v;
                  _apply();
                },
        ),
      ),
      SizedBox(
        width: _controlWidth,
        child: DropdownButtonFormField<MovementCategoryScope>(
          initialValue: _scope,
          key: ValueKey(_scope),
          isExpanded: true,
          itemHeight: null,
          isDense: false,
          decoration: const InputDecoration(labelText: 'Alcance'),
          items: const [
            DropdownMenuItem(
              value: MovementCategoryScope.branch,
              child: Text('Rama completa'),
            ),
            DropdownMenuItem(
              value: MovementCategoryScope.direct,
              child: Text('Solo directos'),
            ),
          ],
          onChanged: c.loading
              ? null
              : (v) {
                  _scope = v!;
                  _apply();
                },
        ),
      ),
      FilledButton(
        onPressed: c.loading ? null : _apply,
        child: const Text('Aplicar filtros'),
      ),
      TextButton(
        onPressed: c.loading
            ? null
            : () {
                _search.clear();
                _accountId = null;
                _categoryId = null;
                _unclassified = false;
                _apply();
              },
        child: const Text('Limpiar filtros'),
      ),
    ],
  );
  Widget _check(MovementRecord row) => SizedBox(
    width: 48,
    height: 48,
    child: Checkbox(
      semanticLabel: 'Seleccionar ${row.data.concept} · ${row.id}',
      value: c.selected.contains(row.id),
      onChanged: (v) => c.toggle(row.id, v!),
    ),
  );
  Widget _openButton(MovementRecord row) => TextButton(
    focusNode: _focus.putIfAbsent(row.id, () => FocusNode()),
    onPressed: () => _open(row.id),
    child: Text('Abrir ${row.data.concept}'),
  );
  List<String> _values(MovementRecord row) => [
    row.data.valueDate.value,
    row.data.concept,
    c.accounts[row.data.accountId] ?? row.data.accountId,
    c.categoryLabel(row.data.categoryId),
    movementEuro(row.data.amountCents),
  ];
  @override
  Widget build(BuildContext context) {
    final wide =
        MediaQuery.sizeOf(context).width >= 840 &&
        MediaQuery.textScalerOf(context).scale(14) < 21;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Movimientos'),
        leading: IconButton(
          tooltip: widget.returnLabel,
          onPressed: widget.onReturn,
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      bottomNavigationBar: widget.bottomNavigation,
      body: _withNavigation(
        SafeArea(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: EdgeInsets.all(wide ? 24 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Periodo ${c.from.value} → ${c.until?.value ?? 'fin del calendario'} · Recientes primero',
                ),
                Text(
                  'Resultados: ${c.accountId == null ? 'Todas las cuentas' : c.accounts[c.accountId] ?? c.accountId} · ${c.unclassified
                      ? 'Sin clasificar'
                      : c.categoryId == null
                      ? 'Todas las categorías'
                      : c.categoryLabel(c.categoryId)} · ${c.scope == MovementCategoryScope.branch ? 'Rama completa' : 'Solo directos'} · Concepto: ${c.concept.isEmpty ? 'Todos' : c.concept}',
                ),
                _filters(),
                if (widget.onCreate != null)
                  FilledButton(
                    onPressed: c.loading
                        ? null
                        : () async {
                            await widget.onCreate!();
                            if (mounted) await c.refresh();
                          },
                    child: const Text('Añadir movimiento'),
                  ),
                if (_validation != null)
                  Semantics(liveRegion: true, child: Text(_validation!)),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    '${c.selected.length} seleccionados · UUID: ${c.selected.join(', ')}',
                  ),
                ),
                if (c.notice != null)
                  Semantics(liveRegion: true, child: Text(c.notice!)),
                Wrap(
                  spacing: 12,
                  children: [
                    OutlinedButton(
                      onPressed:
                          c.loading || c.page == null || c.page!.records.isEmpty
                          ? null
                          : c.selectPage,
                      child: Text(
                        'Seleccionar página visible (${c.page?.records.length ?? 0})',
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        c.clearSelection();
                        _changed();
                      },
                      child: const Text('Quitar selección'),
                    ),
                  ],
                ),
                if (c.loading)
                  Semantics(
                    liveRegion: true,
                    child: Text('Cargando movimientos…'),
                  ),
                if (c.error != null) ...[
                  Semantics(liveRegion: true, child: Text(c.error!)),
                  FilledButton(
                    onPressed: () => c.refresh(),
                    child: const Text('Reintentar'),
                  ),
                ],
                if (c.page != null) ...[
                  Text(
                    'Subtotal filtrado: ${movementEuro(c.page!.subtotalCents)}',
                  ),
                  if (c.page!.records.isEmpty)
                    const Text(
                      'No hay movimientos que coincidan con este periodo y filtros.',
                    ),
                  if (wide && c.page!.records.isNotEmpty)
                    Table(
                      columnWidths: const {
                        0: FixedColumnWidth(48),
                        1: FlexColumnWidth(1),
                        2: FlexColumnWidth(2),
                        3: FlexColumnWidth(1.5),
                        4: FlexColumnWidth(2),
                        5: FlexColumnWidth(1.2),
                        6: FlexColumnWidth(1.5),
                      },
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      children: [
                        TableRow(
                          children: [
                            for (final title in [
                              '',
                              'Fecha',
                              'Concepto',
                              'Cuenta',
                              'Categoría',
                              'Importe EUR',
                              'Detalle',
                            ])
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        for (final row in c.page!.records)
                          TableRow(
                            children: [
                              _check(row),
                              for (final value in _values(row))
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                    value,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              _openButton(row),
                            ],
                          ),
                      ],
                    ),
                  if (!wide)
                    for (final row in c.page!.records)
                      Card(
                        child: SizedBox(
                          width: double.infinity,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _check(row),
                                for (final (index, value) in _values(
                                  row,
                                ).indexed)
                                  Text(
                                    '${['Fecha', 'Concepto', 'Cuenta', 'Categoría', 'Importe EUR'][index]}: $value',
                                  ),
                                _openButton(row),
                              ],
                            ),
                          ),
                        ),
                      ),
                ],
                Wrap(
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: c.loading || c.pageIndex == 0
                          ? null
                          : c.previous,
                      child: const Text('Página anterior'),
                    ),
                    Text('Página ${c.pageIndex + 1}'),
                    TextButton(
                      onPressed: c.loading || c.page?.nextCursor == null
                          ? null
                          : c.next,
                      child: const Text('Página siguiente'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _withNavigation(Widget content) => widget.navigation == null
      ? content
      : Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            widget.navigation!,
            Expanded(child: content),
          ],
        );
}
