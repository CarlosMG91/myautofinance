import 'dart:async';

import 'package:flutter/material.dart';

import '../../budget/budget.dart';
import '../../movements/movements.dart';
import '../domain/monthly_figure_detail.dart';
import '../domain/monthly_status_query.dart';

typedef MonthlyStatusLoader = Future<MonthlyStatusQuery> Function();

/// Estado efímero de la vista, transportado por app en el contexto EP-016.
final class MonthlyStatusPosition {
  const MonthlyStatusPosition({
    this.expanded = const {},
    this.offset = 0,
    this.focus,
    this.categoryId,
    this.scope = MovementCategoryScope.branch,
  });
  final Set<String> expanded;
  final double offset;
  final String? focus, categoryId;
  final MovementCategoryScope scope;
}

class MonthlyStatusScreen extends StatefulWidget {
  const MonthlyStatusScreen({
    super.key,
    required this.load,
    required this.month,
    required this.details,
    required this.onAdd,
    required this.periodControls,
    required this.shell,
    required this.onPosition,
    this.initialPosition = const MonthlyStatusPosition(),
  });
  final MonthlyStatusLoader load;
  final BudgetMonth month;
  final MonthlyStatusDetailCallbacks details;
  final Future<void> Function() onAdd;
  final Widget periodControls;
  final Widget Function(
    Widget body,
    ScrollController scroll,
    Future<void> Function() refresh,
  )
  shell;
  final void Function(MonthlyStatusPosition position) onPosition;
  final MonthlyStatusPosition initialPosition;
  @override
  State<MonthlyStatusScreen> createState() => _MonthlyStatusScreenState();
}

class _MonthlyStatusScreenState extends State<MonthlyStatusScreen> {
  final _scroll = ScrollController();
  final _focusNodes = <String, FocusNode>{};
  late Set<String> _expanded;
  StreamSubscription<int>? _subscription;
  CategoryReadInvalidation? _invalidation;
  MonthlyStatus? _data;
  String? _error, _focus, _category;
  MovementCategoryScope _scope = MovementCategoryScope.branch;
  late double _offset;
  int _request = 0;
  bool _loading = true, _restoring = false;
  bool _refreshNeeded = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _expanded = {...widget.initialPosition.expanded};
    _offset = widget.initialPosition.offset;
    _focus = widget.initialPosition.focus;
    _category = widget.initialPosition.categoryId;
    _scope = widget.initialPosition.scope;
    _scroll.addListener(_publish);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      unawaited(_read());
    }
  }

  @override
  void didUpdateWidget(MonthlyStatusScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month.value != widget.month.value) {
      _expanded.clear();
      _offset = 0;
      _focus = null;
      _category = null;
      _scope = MovementCategoryScope.branch;
      _read();
    } else if (oldWidget.load != widget.load) {
      _read();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scroll.dispose();
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _publish() {
    if (_restoring || _loading || ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    if (_scroll.hasClients) _offset = _scroll.offset;
    widget.onPosition(
      MonthlyStatusPosition(
        expanded: Set.unmodifiable(_expanded),
        offset: _offset,
        focus: _focus,
        categoryId: _category,
        scope: _scope,
      ),
    );
  }

  Future<void> _read() async {
    final request = ++_request;
    if (ModalRoute.of(context)?.isCurrent == false) {
      _refreshNeeded = true;
      _loading = false;
      return;
    }
    _refreshNeeded = false;
    final month = widget.month;
    // Ocultar las filas reduce temporalmente el scroll a cero. No publicar
    // ese ajuste del layout como posición elegida por la persona usuaria.
    _restoring = true;
    setState(() {
      _loading = true;
      _error = null;
      _data = null;
    });
    try {
      // Resolver siempre la conexión activa, también después de restaurar.
      final query = await widget.load();
      if (!mounted || request != _request) return;
      if (ModalRoute.of(context)?.isCurrent == false) {
        _refreshNeeded = true;
        return;
      }
      if (!identical(_invalidation, query.invalidation)) {
        await _subscription?.cancel();
        if (!mounted || request != _request) return;
        _invalidation = query.invalidation;
        _subscription = query.invalidation.changes.listen((_) {
          // Las secundarias pueden estar escribiendo o sustituyendo la base.
          // Su retorno ya solicita una lectura sobre la conexión vigente.
          if (!mounted) return;
          if (ModalRoute.of(context)?.isCurrent == false) {
            _refreshNeeded = true;
            return;
          }
          unawaited(_read());
        });
      }
      final data = await query.read(month);
      if (!mounted || request != _request) return;
      setState(() => _data = data);
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(
        () => _error = error is MonthlyStatusFailure
            ? error.message
            : 'No se pudo consultar el estado del mes. Inténtalo de nuevo.',
      );
    } finally {
      if (mounted && request == _request) {
        setState(() => _loading = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || request != _request) return;
          _restoring = true;
          if (_scroll.hasClients) {
            _scroll.jumpTo(_offset.clamp(0, _scroll.position.maxScrollExtent));
          }
          final focus = _focusNodes[_focus];
          if (ModalRoute.of(context)?.isCurrent != false &&
              focus?.context != null) {
            focus!.requestFocus();
          }
          _restoring = false;
        });
      }
    }
  }

  Future<void> _open(
    String token,
    String? category,
    MovementCategoryScope scope,
    Future<void> Function() action,
  ) async {
    _focus = token;
    _category = category;
    _scope = scope;
    _publish();
    final month = widget.month.value;
    await action();
    if (!mounted || month != widget.month.value) return;
    await _read();
  }

  FocusNode _node(String token) =>
      _focusNodes.putIfAbsent(token, () => FocusNode(debugLabel: token));

  Widget _figure(
    String key,
    String label,
    int cents,
    MonthlyFigureDetail detail,
    OpenMonthlyFigureDetail open, {
    bool missing = false,
    bool registered = false,
    String? difference,
    bool compact = true,
    bool emphasized = false,
  }) {
    final text = missing
        ? 'Sin presupuesto'
        : '${_euro(cents)}${registered && cents == 0 ? ' (registrado)' : ''}';
    return Semantics(
      label:
          '$label · ${widget.month.value.substring(0, 7)} · ${detail.scope == MovementCategoryScope.direct ? 'Solo este nodo' : 'Rama completa'}',
      child: TextButton(
        key: ValueKey(key),
        focusNode: _node(key),
        onFocusChange: (focused) {
          if (focused) {
            _focus = key;
            _category = detail.unclassified
                ? 'sin-clasificar'
                : detail.categoryId;
            _scope = detail.scope;
            _publish();
          }
        },
        style: TextButton.styleFrom(
          foregroundColor:
              difference == null || MediaQuery.highContrastOf(context)
              ? null
              : cents < 0
              ? const Color(0xff9f2733)
              : cents > 0
              ? const Color(0xff166534)
              : const Color(0xff17212b),
          alignment: Alignment.centerRight,
          minimumSize: Size(48, compact ? 40 : 48),
          padding: const EdgeInsets.all(10),
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontSize: emphasized
                ? 20
                : compact
                ? 14
                : 16,
            fontWeight: emphasized ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        onPressed: () => _open(
          key,
          detail.unclassified ? 'sin-clasificar' : detail.categoryId,
          detail.scope,
          () => open(detail),
        ),
        child: Text(
          '$text${difference == null ? '' : '\n$difference'}',
          textAlign: TextAlign.right,
        ),
      ),
    );
  }

  List<Widget> _figures(
    String id,
    String label,
    MonthlyStatusTotals totals,
    int direct, {
    String? category,
    bool unclassified = false,
    bool compact = true,
    bool emphasized = false,
  }) {
    final branch = MonthlyFigureDetail(
      month: widget.month,
      categoryId: category,
      unclassified: unclassified,
    );
    final own = MonthlyFigureDetail(
      month: widget.month,
      categoryId: category,
      unclassified: unclassified,
      scope: MovementCategoryScope.direct,
    );
    return [
      _figure(
        '$id:previsto',
        'Previsto agregado de $label',
        totals.plannedCents,
        branch,
        widget.details.onBudgets,
        missing: !totals.hasBudget,
        registered: totals.hasBudget,
        compact: compact,
        emphasized: emphasized,
      ),
      _figure(
        '$id:directo',
        'Real directo de $label',
        direct,
        own,
        widget.details.onMovements,
        compact: compact,
        emphasized: emphasized,
      ),
      _figure(
        '$id:real',
        'Real agregado de $label',
        totals.actualCents,
        branch,
        widget.details.onMovements,
        compact: compact,
        emphasized: emphasized,
      ),
      _figure(
        '$id:diferencia',
        'Diferencia real menos previsto de $label',
        totals.differenceCents,
        branch,
        widget.details.onDifference,
        difference: _difference(totals.differenceCents),
        compact: compact,
        emphasized: emphasized,
      ),
    ];
  }

  Widget _categoryWidget(
    MonthlyStatusRow row,
    Set<String> parents, {
    required bool compact,
  }) {
    final id = row.categoryId;
    final label =
        '${compact ? row.category.node.name : row.category.path}${row.category.node.archived ? ' · Archivada' : ''}';
    final style = TextStyle(
      fontSize: compact ? 14 : 16,
      fontWeight: !compact || row.category.node.depth == 1
          ? FontWeight.w600
          : FontWeight.normal,
    );
    return Padding(
      padding: EdgeInsets.only(
        left: compact ? 16.0 * (row.category.node.depth - 1) : 0,
      ),
      child: parents.contains(id)
          ? Semantics(
              expanded: _expanded.contains(id),
              label:
                  '${_expanded.contains(id) ? 'Contraer' : 'Expandir'} ${row.category.path}',
              child: TextButton(
                key: ValueKey('$id:expandir'),
                focusNode: _node('$id:expandir'),
                style: TextButton.styleFrom(
                  minimumSize: Size(48, compact ? 40 : 48),
                ),
                onFocusChange: (focused) {
                  if (!focused) return;
                  _focus = '$id:expandir';
                  _category = id;
                  _scope = MovementCategoryScope.branch;
                  _publish();
                },
                onPressed: () {
                  setState(
                    () => _expanded.contains(id)
                        ? _expanded.remove(id)
                        : _expanded.add(id),
                  );
                  _focus = '$id:expandir';
                  _category = id;
                  _scope = MovementCategoryScope.branch;
                  _publish();
                },
                child: Row(
                  children: [
                    Icon(
                      _expanded.contains(id)
                          ? Icons.expand_more
                          : Icons.chevron_right,
                      size: 20,
                    ),
                    Expanded(child: Text(label, style: style)),
                  ],
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(10),
              child: Text(label, style: style),
            ),
    );
  }

  Widget _content(MonthlyStatus data) {
    final parents = {
      for (final row in data.rows)
        if (row.category.node.parentId != null) row.category.node.parentId!,
    };
    final byId = {for (final row in data.rows) row.categoryId: row};
    bool visible(MonthlyStatusRow row) {
      var parent = row.category.node.parentId;
      while (parent != null) {
        if (!_expanded.contains(parent)) return false;
        parent = byId[parent]?.category.node.parentId;
      }
      return true;
    }

    List<List<Widget>> entries(bool compact) => <List<Widget>>[
      for (final row in data.rows.where(visible))
        [
          Tooltip(
            message: row.category.path,
            child: _categoryWidget(row, parents, compact: compact),
          ),
          ..._figures(
            row.categoryId,
            row.category.path,
            row.totals,
            row.actualDirectCents,
            category: row.categoryId,
            compact: compact,
          ),
        ],
      if (data.unclassified.hasMovements)
        [
          const Padding(
            padding: EdgeInsets.all(10),
            child: Text('Sin clasificar'),
          ),
          ..._figures(
            'sin-clasificar',
            'Sin clasificar',
            data.unclassified,
            data.unclassified.actualCents,
            unclassified: true,
            compact: compact,
          ),
        ],
      [
        const Padding(
          padding: EdgeInsets.all(10),
          child: Text(
            'Total firmado',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        ..._figures(
          'total',
          'Total firmado',
          data.total,
          data.total.actualCents,
          compact: compact,
          emphasized: true,
        ),
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                for (final (index, label) in [
                  (0, 'Previsto agregado'),
                  (2, 'Real agregado'),
                  (3, 'Diferencia real − previsto'),
                ])
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label),
                      _figures(
                        'resumen-$index',
                        'Total del mes',
                        data.total,
                        data.total.actualCents,
                        compact: false,
                        emphasized: true,
                      )[index],
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (!data.total.hasMovements)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No hay movimientos en este mes. Real: 0,00 €.'),
          ),
        if (!data.total.hasBudget)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Sin presupuesto en este mes. El previsto aporta cero a la diferencia.',
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Todas las cuentas · Real directo: solo este nodo. Agregados: rama completa. El total suma raíces y Sin clasificar una vez.',
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final table =
                constraints.maxWidth >= 700 &&
                MediaQuery.textScalerOf(context).scale(14) <= 20;
            if (table) {
              return Table(
                key: const ValueKey('monthly-status-table'),
                columnWidths: const {0: FlexColumnWidth(1.8)},
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                border: TableBorder.all(color: const Color(0xffdce2e8)),
                children: [
                  TableRow(
                    decoration: const BoxDecoration(color: Color(0xffedf2f7)),
                    children: [
                      for (final label in [
                        'Categoría',
                        'Previsto agregado',
                        'Real directo',
                        'Real agregado',
                        'Diferencia real − previsto',
                      ])
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  for (final entry in entries(true)) TableRow(children: entry),
                ],
              );
            }
            return Column(
              key: const ValueKey('monthly-status-cards'),
              children: [
                for (final entry in entries(false))
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          entry.first,
                          Text(
                            '${widget.month.value.substring(0, 7)} · Rama completa',
                          ),
                          const SizedBox(height: 12),
                          for (var i = 1; i < entry.length; i++)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  [
                                    'Previsto agregado',
                                    'Real directo',
                                    'Real agregado',
                                    'Diferencia real − previsto',
                                  ][i - 1],
                                ),
                                entry[i],
                              ],
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = ModalRoute.of(context)?.isCurrent != false;
    final refreshDue = _refreshNeeded && !_loading && current;
    if (refreshDue) {
      _refreshNeeded = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_read());
      });
    }
    return widget.shell(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widget.periodControls,
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                key: const ValueKey('status-add'),
                focusNode: _node('status-add'),
                onPressed: () => _open(
                  'status-add',
                  null,
                  MovementCategoryScope.branch,
                  widget.onAdd,
                ),
                child: const Text('Añadir movimiento'),
              ),
              OutlinedButton(
                key: const ValueKey('status-refresh'),
                focusNode: _node('status-refresh'),
                onPressed: () =>
                    _open('status-refresh', _category, _scope, () async {}),
                child: const Text('Actualizar'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading || refreshDue)
            Semantics(
              liveRegion: true,
              child: const Text('Consultando el estado del mes…'),
            )
          else if (_error != null)
            Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_error!),
                  OutlinedButton(
                    onPressed: _read,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            )
          else if (_data != null)
            _content(_data!),
        ],
      ),
      _scroll,
      _read,
    );
  }
}

String _difference(int cents) => cents > 0
    ? 'A favor'
    : cents < 0
    ? 'En contra'
    : 'Sin diferencia';

String _euro(int cents) {
  final amount = BigInt.from(cents).abs();
  final units = (amount ~/ BigInt.from(100)).toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]}.',
  );
  return '${cents < 0
      ? '−'
      : cents > 0
      ? '+'
      : ''}$units,${(amount % BigInt.from(100)).toString().padLeft(2, '0')} €';
}
