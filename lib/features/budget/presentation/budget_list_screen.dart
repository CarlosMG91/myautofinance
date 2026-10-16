import 'dart:async';

import 'package:flutter/material.dart';

import '../../../ui/autofinance_ui.dart';
import '../domain/budget_list_query.dart';
import '../domain/budget_repository.dart';
import '../../movements/movements.dart'
    show CategoryDetails, MovementCategoryScope;
import 'budget_source.dart';
import 'budget_ui.dart';

/// Lista única de partidas; los formularios siguen perteneciendo a EP-011.
class BudgetListScreen extends StatefulWidget {
  const BudgetListScreen({
    super.key,
    required this.load,
    required this.query,
    required this.onReturn,
    required this.onCreate,
    required this.onOpen,
    this.onQueryChanged,
    this.originLabel = 'Informe de origen',
    this.shell,
  });
  final BudgetLoader load;
  final BudgetListQuery query;
  final VoidCallback onReturn;
  final Future<void> Function() onCreate;
  final Future<void> Function(String id) onOpen;
  final ValueChanged<BudgetListQuery>? onQueryChanged;
  final String originLabel;
  final Widget Function(Widget body, ScrollController scroll)? shell;
  @override
  State<BudgetListScreen> createState() => _BudgetListScreenState();
}

class _BudgetListScreenState extends State<BudgetListScreen> {
  final _scroll = ScrollController();
  final _createFocus = FocusNode();
  final _headingFocus = FocusNode();
  final _focus = <String, FocusNode>{};
  final _first = TextEditingController();
  final _last = TextEditingController();
  StreamSubscription<int>? _changes;
  Object? _identity;
  BudgetListResult? _result;
  List<CategoryDetails> _categories = const [];
  late BudgetListQuery _query;
  late String _mode;
  String? _categoryId;
  late MovementCategoryScope _scope;
  bool _loading = true;
  bool _originMissing = false;
  String? _error, _validation;
  int _revision = 0, _scopeRevision = 0, _page = 0;
  static const _pageSize = 100;

  @override
  void initState() {
    super.initState();
    _query = widget.query;
    _draft();
    _read();
  }

  void _draft() {
    _first.text = _query.firstMonth.value.substring(0, 7);
    _last.text = _query.lastMonth.value.substring(0, 7);
    _categoryId = _query.categoryId;
    _scope = _query.scope;
    _mode = _query.isAnnual
        ? 'year'
        : _query.isMonthly
        ? 'month'
        : 'range';
  }

  bool get _modified =>
      _query.firstMonth.value != widget.query.firstMonth.value ||
      _query.lastMonth.value != widget.query.lastMonth.value ||
      _query.categoryId != widget.query.categoryId ||
      _query.scope != widget.query.scope;

  @override
  void dispose() {
    _revision++;
    _changes?.cancel();
    _scroll.dispose();
    _first.dispose();
    _last.dispose();
    _createFocus.dispose();
    _headingFocus.dispose();
    for (final focus in _focus.values) {
      focus.dispose();
    }
    super.dispose();
  }

  Future<void> _read({bool restart = false}) async {
    final revision = ++_revision;
    final query = _query;
    setState(() {
      if (restart) _page = 0;
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final source = await widget.load();
      if (!mounted || revision != _revision) return;
      final reader = source.entries;
      if (reader == null) {
        throw const BudgetFailure('Lista de partidas no disponible.');
      }
      if (!identical(_identity, source.identity)) {
        final replaced = _identity != null;
        await _changes?.cancel();
        if (!mounted || revision != _revision) return;
        _identity = source.identity;
        if (replaced) {
          _page = 0;
          _scopeRevision++;
        }
        _changes = reader.invalidation.changes.listen((_) {
          _read(restart: true);
        });
      }
      final categories = await source.categories();
      if (!mounted || revision != _revision) return;
      setState(() {
        _categories = categories;
        _originMissing =
            widget.query.categoryId != null &&
            !categories.any((c) => c.node.id == widget.query.categoryId);
      });
      final result = await reader.readResult(query);
      if (!mounted || revision != _revision) return;
      setState(() {
        _categories = categories;
        _result = result;
        if (_page * _pageSize >= result.totalCount) _page = 0;
      });
    } catch (e) {
      if (mounted && revision == _revision) {
        setState(() => _error = budgetError(e));
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  void _change(BudgetListQuery query) {
    _scopeRevision++;
    setState(() {
      _query = query;
      _validation = null;
      _draft();
    });
    widget.onQueryChanged?.call(query);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _read(restart: true);
  }

  void _apply() {
    try {
      BudgetMonth month(String text) {
        if (!RegExp(r'^[0-9]{4}-(0[1-9]|1[0-2])$').hasMatch(text.trim())) {
          throw const BudgetFailure('Usa meses con formato AAAA-MM.');
        }
        return BudgetMonth.parse('${text.trim()}-01');
      }

      final first = month(_first.text);
      final year = int.parse(first.value.substring(0, 4));
      _change(switch (_mode) {
        'year' => BudgetListQuery.annual(
          year,
          focusedMonth: int.parse(_query.month.value.substring(5, 7)),
          categoryId: _categoryId,
          scope: _scope,
        ),
        'month' => BudgetListQuery(
          month: first,
          categoryId: _categoryId,
          scope: _scope,
        ),
        _ => BudgetListQuery.range(
          month: _query.month,
          firstMonth: first,
          lastMonth: month(_last.text),
          categoryId: _categoryId,
          scope: _scope,
        ),
      });
    } catch (e) {
      setState(() => _validation = 'Filtros sin aplicar: ${budgetError(e)}');
    }
  }

  Future<void> _open(String? id) async {
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final scopeRevision = _scopeRevision;
    await (id == null ? widget.onCreate() : widget.onOpen(id));
    if (!mounted) return;
    await _read();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || scopeRevision != _scopeRevision) return;
      if (_scroll.hasClients) {
        _scroll.jumpTo(offset.clamp(0.0, _scroll.position.maxScrollExtent));
      }
      final focus = id == null ? _createFocus : _focus[id];
      (focus?.context == null ? _headingFocus : focus!).requestFocus();
    });
  }

  String _label(BudgetListQuery query) {
    final category = _categories
        .where((c) => c.node.id == query.categoryId)
        .firstOrNull;
    return '${query.firstMonth.value.substring(0, 7)} – ${query.lastMonth.value.substring(0, 7)} · '
        '${query.categoryId == null ? 'Todas las categorías' : category?.path ?? query.categoryId} · '
        '${query.scope == MovementCategoryScope.direct ? 'Solo directos' : 'Rama completa'}';
  }

  Widget _filters() {
    final width = MediaQuery.sizeOf(context).width < 600
        ? double.infinity
        : 260.0;
    Widget field(Widget child) => SizedBox(width: width, child: child);
    return AfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          Text(
            'Filtrar partidas',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              field(
                DropdownButtonFormField<String>(
                  key: ValueKey('mode-$_mode'),
                  initialValue: _mode,
                  isExpanded: true,
                  isDense: false,
                  itemHeight: null,
                  decoration: const InputDecoration(labelText: 'Periodo'),
                  items: const [
                    DropdownMenuItem(value: 'month', child: Text('Mes')),
                    DropdownMenuItem(
                      value: 'year',
                      child: Text('Año completo'),
                    ),
                    DropdownMenuItem(
                      value: 'range',
                      child: Text('Rango de meses'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _mode = value!),
                ),
              ),
              field(
                TextField(
                  controller: _first,
                  decoration: InputDecoration(
                    labelText: _mode == 'year'
                        ? 'Mes del año · AAAA-MM'
                        : 'Desde · AAAA-MM',
                  ),
                  onSubmitted: (_) => _apply(),
                ),
              ),
              if (_mode == 'range')
                field(
                  TextField(
                    controller: _last,
                    decoration: const InputDecoration(
                      labelText: 'Hasta inclusivo · AAAA-MM',
                    ),
                    onSubmitted: (_) => _apply(),
                  ),
                ),
              field(
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    'category-$_categoryId-${_categories.map((c) => c.path).join()}',
                  ),
                  initialValue: _categoryId ?? '',
                  isExpanded: true,
                  isDense: false,
                  itemHeight: null,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Todas las categorías'),
                    ),
                    if (_categoryId != null &&
                        !_categories.any((c) => c.node.id == _categoryId))
                      DropdownMenuItem(
                        value: _categoryId,
                        child: Text(_categoryId!),
                      ),
                    for (final category in _categories)
                      DropdownMenuItem(
                        value: category.node.id,
                        child: Text(
                          '${category.path}${category.node.archived ? ' · Archivada' : ''} · ${category.node.id.substring(0, 8)}',
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _categoryId = value == '' ? null : value),
                ),
              ),
              field(
                DropdownButtonFormField<MovementCategoryScope>(
                  key: ValueKey(_scope),
                  initialValue: _scope,
                  isExpanded: true,
                  isDense: false,
                  itemHeight: null,
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
                  onChanged: (value) => setState(() => _scope = value!),
                ),
              ),
              FilledButton(
                onPressed: _apply,
                child: const Text('Aplicar filtros'),
              ),
            ],
          ),
          if (_validation != null)
            AfStatus(kind: AfStatusKind.error, message: _validation!),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final entries =
        result?.page(offset: _page * _pageSize) ?? <BudgetListEntry>[];
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 16,
      children: [
        Focus(
          focusNode: _headingFocus,
          child: AfCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Text(
                  'Origen: ${widget.originLabel}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('Ámbito del informe: ${_label(widget.query)}'),
                const Text(
                  'Se consultan los datos actuales. La cifra puede variar si cambió la base; restablecer recupera filtros, no datos anteriores.',
                ),
                Text(
                  _modified
                      ? 'Nuevo ámbito local: ${_label(_query)}'
                      : 'Filtros del informe',
                ),
                TextButton(
                  onPressed: _originMissing
                      ? null
                      : () => _change(widget.query),
                  child: const Text('Restablecer filtros del informe'),
                ),
                if (_originMissing)
                  const AfStatus(
                    kind: AfStatusKind.error,
                    message: 'La categoría del informe ya no existe. Vuelve al origen para elegir otro ámbito.',
                  ),
              ],
            ),
          ),
        ),
        if (widget.shell == null)
          TextButton(
            onPressed: widget.onReturn,
            child: const Text('Volver al origen'),
          ),
        if (result != null)
          AfCard(
            tone: AfCardTone.budget,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Text('Resultados del ámbito: ${result.totalCount} partidas'),
                AfNumericText(
                  'Total de partidas: ${budgetTotal(result.subtotalCents)}',
                ),
                Text(
                  '${entries.length} visibles · el subtotal incluye todas las páginas',
                ),
              ],
            ),
          ),
        _filters(),
        if (_loading)
          const AfStatus(
            kind: AfStatusKind.loading,
            message: 'Cargando partidas…',
          ),
        if (_error != null) ...[
          const Text('No se pudo abrir este detalle'),
          AfStatus(kind: AfStatusKind.error, message: _error!),
          TextButton(onPressed: _read, child: const Text('Reintentar')),
        ],
        if (result != null) ...[
          if (entries.isEmpty)
            const AfStatus(
              kind: AfStatusKind.empty,
              message: 'Sin presupuesto · No hay partidas en este alcance.',
            ),
          for (final entry in entries)
            AfCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  Text(
                    '${entry.category.path}${entry.category.node.archived ? ' · Archivada' : ''}',
                  ),
                  AfNumericText(budgetEuro(entry.record.data.amountCents)),
                  if (!_query.isMonthly)
                    Text(entry.record.data.month.value.substring(0, 7)),
                  Text(entry.record.id),
                  TextButton(
                    focusNode: _focus.putIfAbsent(
                      entry.record.id,
                      FocusNode.new,
                    ),
                    onPressed: () => _open(entry.record.id),
                    child: const Text('Abrir'),
                  ),
                ],
              ),
            ),
          Wrap(
            spacing: 12,
            children: [
              TextButton(
                onPressed: _page == 0 ? null : () => setState(() => _page--),
                child: const Text('Página anterior'),
              ),
              Text('Página ${_page + 1}'),
              TextButton(
                onPressed: (_page + 1) * _pageSize >= result.totalCount
                    ? null
                    : () => setState(() => _page++),
                child: const Text('Página siguiente'),
              ),
            ],
          ),
          FilledButton(
            focusNode: _createFocus,
            onPressed: () => _open(null),
            child: const Text('Crear partida'),
          ),
        ],
      ],
    );
    if (widget.shell != null) return widget.shell!(body, _scroll);
    return Scaffold(
      appBar: AppBar(title: const Text('Partidas del periodo')),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.all(16),
          child: body,
        ),
      ),
    );
  }
}
