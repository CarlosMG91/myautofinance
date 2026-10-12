import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/annual_budget_query.dart';
import '../domain/budget_repository.dart';
import 'annual_budget_cards.dart';
import 'budget_source.dart';
import 'budget_ui.dart';

/// Consulta anual y edición de una partida propia. La composición aporta
/// navegación y controles EP-016; las escrituras pertenecen a EP-011.
class AnnualBudgetScreen extends StatefulWidget {
  const AnnualBudgetScreen({
    super.key,
    required this.load,
    required this.year,
    required this.focusedMonth,
    required this.shell,
    required this.controls,
    required this.openMonth,
    required this.openYear,
    required this.openCell,
    required this.openCapture,
    required this.onOrigin,
    this.openProposal,
    this.initialExpanded = const {},
    this.initialExpandedMonths = const {},
    this.initialScrollOffset = 0,
    this.initialFocus,
  });
  final BudgetLoader load;
  final int year, focusedMonth;
  final Widget Function(
    Widget child,
    Future<bool> Function() canLeave,
    Future<void> Function() refresh,
    ScrollController scroll,
  )
  shell;
  final Widget Function(Future<bool> Function() canLeave) controls;
  final Future<void> Function(int month, String? categoryId) openMonth;
  final Future<void> Function(String? categoryId) openYear;
  final Future<void> Function(int month, String categoryId, String? budgetId)
  openCell;
  final Future<void> Function() openCapture;
  final Future<void> Function()? openProposal;
  final void Function(
    Set<String> expanded,
    double offset,
    String? focus,
    Set<String> months,
  )
  onOrigin;
  final Set<String> initialExpanded;
  final Set<String> initialExpandedMonths;
  final double initialScrollOffset;
  final String? initialFocus;

  @override
  State<AnnualBudgetScreen> createState() => _AnnualBudgetScreenState();
}

class _AnnualBudgetScreenState extends BudgetDraftState<AnnualBudgetScreen> {
  static const _months = [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];
  AnnualBudget? _data;
  BudgetSource? _source;
  Object? _draftIdentity;
  AnnualBudgetRow? _draftRow;
  AnnualBudgetCell? _draftCell;
  String? _error, _readError, _focusToken;
  final _amount = TextEditingController();
  final _amountFocus = FocusNode();
  final _matrixFocus = FocusNode();
  final _scroll = ScrollController();
  final _vertical = ScrollController();
  final _header = ScrollController(), _horizontal = ScrollController();
  final _focuses = <String, FocusNode>{};
  late final Set<String> _expanded = {...widget.initialExpanded};
  late final Set<String> _expandedMonths = {...widget.initialExpandedMonths};
  bool _restoreFocus = false;
  StreamSubscription<int>? _subscription;
  Object? _subscribedInvalidation;
  bool _loading = true, _syncingScroll = false, _initial = true;
  bool _opening = false;
  int _request = 0;
  double _initialHorizontal = 0, _initialVertical = 0;

  @override
  bool get dirty =>
      _draftCell != null &&
      _amount.text !=
          (_draftCell!.ownAmountCents == null
              ? ''
              : budgetDecimal(_draftCell!.ownAmountCents!));

  @override
  bool get locked =>
      super.locked || (_opening && ModalRoute.of(context)?.isCurrent != false);

  @override
  void initState() {
    super.initState();
    _focusToken = widget.initialFocus;
    final position = RegExp(r'^(.*)\|matrix=([0-9.]+),([0-9.]+)$')
        .firstMatch(_focusToken ?? '');
    if (position != null) {
      _focusToken = position[1];
      final horizontal = double.tryParse(position[2]!);
      final vertical = double.tryParse(position[3]!);
      if (horizontal != null &&
          vertical != null &&
          horizontal.isFinite &&
          vertical.isFinite) {
        _initialHorizontal = horizontal;
        _initialVertical = vertical;
      }
    }
    _scroll.addListener(_publish);
    _vertical.addListener(_publish);
    _header.addListener(() => _sync(_header, _horizontal));
    _horizontal.addListener(() {
      _sync(_horizontal, _header);
      _publish();
    });
    _read();
  }

  void _sync(ScrollController from, ScrollController to) {
    if (_syncingScroll || !from.hasClients || !to.hasClients) return;
    _syncingScroll = true;
    to.jumpTo(from.offset.clamp(0, to.position.maxScrollExtent));
    _syncingScroll = false;
  }

  @override
  void didUpdateWidget(AnnualBudgetScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.year != widget.year ||
        oldWidget.focusedMonth != widget.focusedMonth) {
      _initial = false;
      _focusToken = null;
      FocusManager.instance.primaryFocus?.unfocus();
      if (oldWidget.year != widget.year) unawaited(_read(resetPosition: true));
      final year = widget.year, month = widget.focusedMonth;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.year != year || widget.focusedMonth != month) {
          return;
        }
        for (final controller in [_scroll, _vertical, _horizontal, _header]) {
          if (controller.hasClients) controller.jumpTo(0);
        }
        _publish();
      });
    }
  }

  @override
  void dispose() {
    _request++;
    _subscription?.cancel();
    _amount.dispose();
    _amountFocus.dispose();
    _matrixFocus.dispose();
    for (final controller in [_scroll, _vertical, _header, _horizontal]) {
      controller.dispose();
    }
    for (final focus in _focuses.values) {
      focus.dispose();
    }
    super.dispose();
  }

  Future<void> _read({bool resetPosition = false}) async {
    final request = ++_request;
    final year = widget.year;
    final outer = resetPosition
        ? 0.0
        : _initial
        ? widget.initialScrollOffset
        : (_scroll.hasClients ? _scroll.offset : 0.0);
    final vertical = _initial
        ? _initialVertical
        : !resetPosition && _vertical.hasClients
        ? _vertical.offset
        : 0.0;
    final horizontal = _initial
        ? _initialHorizontal
        : !resetPosition && _horizontal.hasClients
        ? _horizontal.offset
        : 0.0;
    setState(() {
      _loading = true;
      _readError = null;
      _data = null;
    });
    try {
      final source = await widget.load();
      if (!mounted || request != _request) return;
      final query = source.annual;
      if (query == null) {
        throw const AnnualBudgetFailure(
          'La consulta anual no está disponible.',
          code: AnnualBudgetFailureCode.persistence,
        );
      }
      if (!identical(_subscribedInvalidation, query.invalidation)) {
        await _subscription?.cancel();
        if (!mounted || request != _request) return;
        _subscribedInvalidation = query.invalidation;
        _subscription = query.invalidation.changes.listen((_) => _read());
      }
      final data = await query.read(year);
      if (!mounted || request != _request || widget.year != year) return;
      setState(() {
        _data = data;
        _source = source;
      });
    } catch (error) {
      if (mounted && request == _request) {
        setState(() {
          _readError = error is AnnualBudgetFailure
              ? error.message
              : budgetError(error);
        });
      }
    } finally {
      if (mounted && request == _request) {
        setState(() => _loading = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || request != _request) return;
          for (final (controller, offset) in [
            (_scroll, outer),
            (_vertical, vertical),
            (_horizontal, horizontal),
            (_header, horizontal),
          ]) {
            if (controller.hasClients) {
              controller.jumpTo(
                offset.clamp(0, controller.position.maxScrollExtent),
              );
            }
          }
          if ((_initial || _restoreFocus) && _data != null) {
            _initial = false;
            _restoreFocus = false;
            final focus = _focuses[_focusToken];
            if (focus?.context != null) focus!.requestFocus();
          }
        });
      }
    }
  }

  void _publish() {
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
    final position =
        _horizontal.hasClients &&
            _vertical.hasClients &&
            (_focusToken != null ||
                _horizontal.offset > 0 ||
                _vertical.offset > 0)
        ? '${_focusToken ?? 'matrix'}|matrix=${_horizontal.offset.toStringAsFixed(3)},${_vertical.offset.toStringAsFixed(3)}'
        : _focusToken;
    widget.onOrigin(
      {..._expanded},
      _scroll.hasClients ? _scroll.offset : 0,
      position,
      {..._expandedMonths},
    );
  }

  void _clear() {
    setState(() {
      _draftCell = null;
      _draftRow = null;
      _draftIdentity = null;
      _error = null;
    });
  }

  Future<bool> _canLeave() async {
    if (locked || !await discard() || !mounted) return false;
    _clear();
    return true;
  }

  Future<void> _begin(AnnualBudgetRow row, AnnualBudgetCell cell) async {
    if (!await _canLeave() || !mounted) return;
    setState(() {
      _draftRow = row;
      _draftCell = cell;
      _draftIdentity = _source!.identity;
      _amount.text = cell.ownAmountCents == null
          ? ''
          : budgetDecimal(cell.ownAmountCents!);
      _error = null;
    });
    _focusToken = _token(row, cell);
    _publish();
    _amountFocus.requestFocus();
  }

  Future<void> _save() async {
    if (locked || _draftCell == null || _loading || _data == null) return;
    final row = _draftRow!, cell = _draftCell!;
    setState(() {
      busy = true;
      _error = null;
    });
    try {
      if (int.parse(cell.month.value.substring(0, 4)) != widget.year) {
        throw const BudgetFailure(
          'El borrador pertenece a otro año. Vuelve a ese año o descártalo explícitamente antes de escribir.',
        );
      }
      final amount = parseBudgetAmount(_amount.text);
      final source = await widget.load();
      if (!identical(source.identity, _draftIdentity)) {
        throw const BudgetFailure(
          'La base local se ha sustituido. Conserva tu borrador y vuelve a abrir el año antes de escribir.',
        );
      }
      if (cell.ownBudget == null) {
        await source.management.create(
          month: cell.month,
          categoryId: row.categoryId,
          amountCents: amount,
        );
      } else {
        await source.management.edit(cell.ownBudget!.id, amountCents: amount);
      }
      if (!mounted) return;
      _clear();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Partida guardada')));
      await _read();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              '${cell.month.value.substring(0, 7)} · ${row.category.path}\n${budgetError(error)}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              widget.year != int.parse(cell.month.value.substring(0, 4))) {
            return;
          }
          final focus = _draftCell == null
              ? _focuses[_token(row, cell)]
              : _amountFocus;
          if (focus?.context != null) focus!.requestFocus();
        });
      }
    }
  }

  Future<void> _open(Future<void> Function() action, String token) async {
    if (!await _canLeave() || !mounted) return;
    _focusToken = token;
    _publish();
    setState(() => _opening = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(budgetError(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
        _restoreFocus = ModalRoute.of(context)?.isCurrent != false;
        await _read();
      }
    }
  }

  String _token(AnnualBudgetRow row, AnnualBudgetCell cell) =>
      '${row.categoryId}:${cell.month.value.substring(5, 7)}';

  FocusNode _focus(String token) =>
      _focuses.putIfAbsent(token, () => FocusNode());

  Future<void> _openDraftForm() {
    final row = _draftRow!, cell = _draftCell!;
    return _open(
      () => widget.openCell(
        int.parse(cell.month.value.substring(5, 7)),
        row.categoryId,
        cell.ownBudget!.id,
      ),
      _token(row, cell),
    );
  }

  List<AnnualBudgetRow> get _visible {
    final rows = _data!.rows;
    final byId = {for (final row in rows) row.categoryId: row};
    return rows.where((row) {
      var parent = row.category.node.parentId;
      while (parent != null) {
        if (!_expanded.contains(parent)) return false;
        parent = byId[parent]?.category.node.parentId;
      }
      return true;
    }).toList();
  }

  bool get _inlineDraftVisible =>
      _data != null &&
      _draftCell != null &&
      int.parse(_draftCell!.month.value.substring(0, 4)) == widget.year &&
      _visible.any((row) => row.categoryId == _draftRow!.categoryId);

  Widget _category(AnnualBudgetRow row) {
    final node = row.category.node;
    final children = _data!.rows.any(
      (r) => r.category.node.parentId == row.categoryId,
    );
    return Padding(
      padding: EdgeInsets.only(left: 8 + (node.depth - 1) * 12),
      child: Row(
        children: [
          if (children)
            IconButton(
              key: ValueKey('expand-${node.id}'),
              tooltip:
                  '${_expanded.contains(node.id) ? 'Contraer' : 'Expandir'} ${row.category.path}',
              icon: Icon(
                _expanded.contains(node.id)
                    ? Icons.expand_less
                    : Icons.expand_more,
              ),
              onPressed: locked
                  ? null
                  : () async {
                      if (_draftRow != null && !await _canLeave()) return;
                      if (!mounted) return;
                      setState(() {
                        if (!_expanded.remove(node.id)) _expanded.add(node.id);
                      });
                      _publish();
                    },
            ),
          Expanded(
            child: Tooltip(
              message: row.category.path,
              child: Text(
                '${node.name}${node.archived ? ' · Archivada' : ''}',
                style: TextStyle(
                  fontWeight: node.depth == 1
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _total(
    AnnualBudgetTotal total,
    String token,
    Future<void> Function() action,
  ) => TextButton(
    key: ValueKey(token),
    focusNode: _focus(token),
    onPressed: locked ? null : () => _open(action, token),
    child: Text(
      '${budgetTotal(total.hasBudget ? BigInt.from(total.amountCents) : null)}\n${total.budgetCount} ${total.budgetCount == 1 ? 'partida' : 'partidas'} · Ver origen',
    ),
  );

  Widget _cell(
    AnnualBudgetRow row,
    AnnualBudgetCell cell, {
    required bool compact,
    bool focused = false,
  }) {
    final token = '${_token(row, cell)}${focused ? ':focused' : ''}';
    if (!compact &&
        _draftRow?.categoryId == row.categoryId &&
        _draftCell?.month.value == cell.month.value) {
      return Padding(padding: const EdgeInsets.all(8), child: _inlineEditor());
    }
    final subtotal = cell.ownBudget == null && cell.total.hasBudget;
    final archivedAbsence =
        row.category.node.archived && !cell.hasOwnBudget && !subtotal;
    return Semantics(
      label: '${row.category.path}, ${cell.month.value.substring(0, 7)}',
      child: TextButton(
        key: ValueKey('cell-$token'),
        focusNode: _focus(token),
        style: TextButton.styleFrom(
          backgroundColor: subtotal ? const Color(0xffeef2f6) : null,
        ),
        onPressed: locked || archivedAbsence
            ? null
            : () => subtotal
                  ? _open(
                      () => widget.openMonth(
                        int.parse(cell.month.value.substring(5, 7)),
                        row.categoryId,
                      ),
                      token,
                    )
                  : compact
                  ? _open(
                      () => widget.openCell(
                        int.parse(cell.month.value.substring(5, 7)),
                        row.categoryId,
                        cell.ownBudget?.id,
                      ),
                      token,
                    )
                  : _begin(row, cell),
        child: Text(
          subtotal
              ? '${budgetTotal(BigInt.from(cell.total.amountCents))}\nSubtotal · Ver partidas\nSin presupuesto propio'
              : '${budgetEuro(cell.ownAmountCents)}\n${archivedAbsence
                    ? 'Archivada'
                    : cell.hasOwnBudget
                    ? 'Propio · Editar'
                    : 'Crear partida'}',
        ),
      ),
    );
  }

  Widget _inlineEditor() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      TextField(
        key: const Key('annual-cell-input'),
        controller: _amount,
        focusNode: _amountFocus,
        enabled: !locked,
        keyboardType: const TextInputType.numberWithOptions(
          signed: true,
          decimal: true,
        ),
        decoration: const InputDecoration(labelText: 'Importe propio EUR'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _save(),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Confirmar celda',
            icon: const Icon(Icons.check),
            onPressed: locked || _loading ? null : _save,
          ),
          IconButton(
            tooltip: 'Cancelar edición',
            icon: const Icon(Icons.close),
            onPressed: locked ? null : _canLeave,
          ),
          if (_draftCell!.ownBudget != null)
            IconButton(
              tooltip: 'Formulario / Eliminar partida',
              icon: const Icon(Icons.edit_note),
              onPressed: locked ? null : _openDraftForm,
            ),
        ],
      ),
    ],
  );

  Widget _editor() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '${_draftCell!.month.value.substring(0, 7)} · ${_draftRow!.category.path}',
      ),
      TextField(
        key: const Key('annual-cell-input'),
        controller: _amount,
        focusNode: _amountFocus,
        enabled: !locked,
        keyboardType: const TextInputType.numberWithOptions(
          signed: true,
          decimal: true,
        ),
        decoration: const InputDecoration(labelText: 'Importe propio EUR'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _save(),
      ),
      Wrap(
        spacing: 8,
        children: [
          FilledButton(
            onPressed: locked || _loading || _data == null ? null : _save,
            child: Text(busy ? 'Guardando…' : 'Confirmar celda'),
          ),
          TextButton(
            onPressed: locked ? null : _canLeave,
            child: const Text('Cancelar edición'),
          ),
          if (_draftCell!.ownBudget != null)
            TextButton(
              onPressed: locked ? null : _openDraftForm,
              child: const Text('Formulario / Eliminar partida'),
            ),
        ],
      ),
      if (_error != null)
        Semantics(
          liveRegion: true,
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );

  Widget _matrix() {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final cellWidth = 180.0 * scale;
    final categoryWidth = 240.0 * scale;
    final height = 104.0 * scale;
    final rows = _visible;
    double rowHeight(AnnualBudgetRow? row) =>
        row?.categoryId == _draftRow?.categoryId && row != null
        ? 144.0 * scale
        : height;
    Widget box(
      Widget child,
      double width, {
      double? fixedHeight,
      bool focused = false,
    }) => Container(
      width: width,
      height: fixedHeight ?? height,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: focused
            ? const Color(0xffeaf3fb)
            : Theme.of(context).colorScheme.surface,
        border: const Border(bottom: BorderSide(color: Color(0xffdbe2ea))),
      ),
      child: child,
    );
    Widget figures(AnnualBudgetRow? row) => Row(
      children: [
        for (var m = 0; m < 12; m++)
          box(
            row == null
                ? _total(
                    _data!.months[m],
                    'total-month-${m + 1}',
                    () => widget.openMonth(m + 1, null),
                  )
                : _cell(row, row.months[m], compact: false),
            cellWidth,
            fixedHeight: rowHeight(row),
            focused: m + 1 == widget.focusedMonth,
          ),
        box(
          _total(
            row?.annualTotal ?? _data!.annualTotal,
            'total-year-${row?.categoryId ?? 'all'}',
            () => widget.openYear(row?.categoryId),
          ),
          cellWidth,
          fixedHeight: rowHeight(row),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Desplaza la matriz con la barra horizontal o enfoca la región y usa ← →. Categoría y cabecera permanecen visibles.',
        ),
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                _moveHorizontal(cellWidth),
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                _moveHorizontal(-cellWidth),
          },
          child: Focus(
            key: const Key('matrix-scroll-region'),
            focusNode: _matrixFocus,
            child: Semantics(
              label: 'Matriz anual ${widget.year}',
              container: true,
              child: Column(
                children: [
                  Row(
                    children: [
                      box(
                        const Text('Categoría'),
                        categoryWidth,
                        fixedHeight: 56 * scale,
                      ),
                      Expanded(
                        child: Scrollbar(
                          controller: _header,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _header,
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (var m = 0; m < 12; m++)
                                  box(
                                    Text(
                                      '${_months[m]}${m + 1 == widget.focusedMonth ? ' · Enfocado' : ''}',
                                    ),
                                    cellWidth,
                                    fixedHeight: 56 * scale,
                                    focused: m + 1 == widget.focusedMonth,
                                  ),
                                box(
                                  const Text('Total anual'),
                                  cellWidth,
                                  fixedHeight: 56 * scale,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                    height: (MediaQuery.sizeOf(context).height * .5).clamp(
                      240,
                      620,
                    ),
                    child: Scrollbar(
                      controller: _vertical,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _vertical,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: categoryWidth,
                              child: Column(
                                children: [
                                  for (final row in rows)
                                    box(
                                      _category(row),
                                      categoryWidth,
                                      fixedHeight: rowHeight(row),
                                    ),
                                  box(
                                    const Text('Total mensual · solo raíces'),
                                    categoryWidth,
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: SizedBox(
                                height: rows.fold<double>(
                                  height,
                                  (sum, row) => sum + rowHeight(row),
                                ),
                                child: Scrollbar(
                                  controller: _horizontal,
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    controller: _horizontal,
                                    scrollDirection: Axis.horizontal,
                                    child: Column(
                                      children: [
                                        for (final row in rows) figures(row),
                                        figures(null),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _moveHorizontal(double delta) {
    if (_horizontal.hasClients) {
      _horizontal.jumpTo(
        (_horizontal.offset + delta).clamp(
          0,
          _horizontal.position.maxScrollExtent,
        ),
      );
    }
  }

  Widget _cards() => AnnualBudgetCards(
    rows: _visible,
    months: _months,
    focusedMonth: widget.focusedMonth,
    expandedMonths: _expandedMonths,
    onExpandMonths: (id, expanded) {
      if (expanded) {
        _expandedMonths.add(id);
      } else {
        _expandedMonths.remove(id);
      }
      _publish();
    },
    category: _category,
    cell: (row, month, focused) =>
        _cell(row, row.months[month - 1], compact: true, focused: focused),
    total: (row) => _total(
      row.annualTotal,
      'total-year-${row.categoryId}',
      () => widget.openYear(row.categoryId),
    ),
    monthTotal: (month) => _total(
      _data!.months[month - 1],
      'total-month-$month',
      () => widget.openMonth(month, null),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: allowPop || (!dirty && !locked),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) leave(() => Navigator.of(context).pop());
    },
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_draftCell != null) _canLeave();
        },
      },
      child: widget.shell(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            widget.controls(_canLeave),
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  focusNode: _focus('capture'),
                  onPressed: locked
                      ? null
                      : () => _open(widget.openCapture, 'capture'),
                  child: const Text('Captura mensual'),
                ),
                TextButton(
                  focusNode: _focus('proposal'),
                  onPressed: locked || widget.openProposal == null
                      ? null
                      : () => _open(widget.openProposal!, 'proposal'),
                  child: const Text('Preparar año siguiente'),
                ),
                TextButton(
                  onPressed: locked ? null : _read,
                  child: const Text('Actualizar año'),
                ),
              ],
            ),
            const Text(
              'Propio: editable · Subtotal: solo lectura · Sin presupuesto: ausencia · Cero registrado: partida existente',
            ),
            const Text(
              'Cada confirmación guarda solo una partida. Vaciar no elimina. El borrado se confirma en el formulario.',
            ),
            if (_draftCell != null &&
                (MediaQuery.sizeOf(context).width < 848 ||
                    _loading ||
                    !_inlineDraftVisible))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _editor(),
                ),
              ),
            if (_draftCell != null &&
                MediaQuery.sizeOf(context).width >= 848 &&
                _inlineDraftVisible &&
                !_loading) ...[
              Text(
                'Editando ${_draftCell!.month.value.substring(0, 7)} · ${_draftRow!.category.path}',
              ),
              if (_error != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
            if (_loading)
              Semantics(
                liveRegion: true,
                child: const Text('Cargando presupuesto anual…'),
              ),
            if (_readError != null)
              Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_readError!),
                    TextButton(
                      onPressed: locked ? null : _read,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            if (_data != null) ...[
              const SizedBox(height: 12),
              Text(
                'Total anual ${widget.year}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              _total(
                _data!.annualTotal,
                'summary-year',
                () => widget.openYear(null),
              ),
              if (!_data!.annualTotal.hasBudget)
                const Text(
                  'Este año no tiene partidas. El árbol activo permite capturarlas.',
                ),
              LayoutBuilder(
                builder: (context, constraints) =>
                    Theme.of(context).platform == TargetPlatform.android ||
                        MediaQuery.sizeOf(context).width < 848 ||
                        constraints.maxWidth < 600
                    ? _cards()
                    : _matrix(),
              ),
            ],
          ],
        ),
        _canLeave,
        _read,
        _scroll,
      ),
    ),
  );
}
