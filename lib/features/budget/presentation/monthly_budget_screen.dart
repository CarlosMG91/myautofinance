import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/budget_repository.dart';
import '../domain/monthly_budget_query.dart';
import '../../movements/movements.dart';
import 'budget_source.dart';
import 'budget_ui.dart';

class MonthlyBudgetScreen extends StatefulWidget {
  const MonthlyBudgetScreen({
    super.key,
    required this.load,
    required this.month,
    required this.onOpen,
    required this.onNavigate,
    required this.destinations,
    required this.management,
    this.periodControls,
  });
  final BudgetLoader load;
  final BudgetMonth month;
  final Future<void> Function(MonthlyBudgetRow? row, BudgetMonth month) onOpen;
  final void Function(String path, BudgetMonth month) onNavigate;
  final Map<String, String> destinations;
  final Widget Function(
    BudgetMonth month,
    Future<void> Function() refresh,
    Future<bool> Function() canOpen,
  )
  management;
  final Widget Function(
    BudgetMonth month,
    Future<bool> Function(BudgetMonth month) change,
  )?
  periodControls;
  @override
  State<MonthlyBudgetScreen> createState() => _MonthlyBudgetScreenState();
}

class _MonthlyBudgetScreenState extends BudgetDraftState<MonthlyBudgetScreen> {
  late BudgetMonth _month;
  MonthlyBudget? _data;
  Object? _identity;
  List<CategoryDetails> _categories = [];
  StreamSubscription<int>? _subscription;
  final _amount = TextEditingController(), _year = TextEditingController();
  final _amountFocus = FocusNode();
  final _scroll = ScrollController();
  final _cellFocus = <String, FocusNode>{};
  MonthlyBudgetRow? _draft;
  String? _error, _readError;
  bool _loading = true;
  int _request = 0;
  @override
  bool get dirty =>
      _draft != null &&
      _amount.text !=
          (_draft!.ownAmountCents == null
              ? ''
              : budgetDecimal(_draft!.ownAmountCents!));
  @override
  void initState() {
    super.initState();
    _month = widget.month;
    _year.text = _month.value.substring(0, 4);
    _read();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _amount.dispose();
    _year.dispose();
    _amountFocus.dispose();
    _scroll.dispose();
    for (final f in _cellFocus.values) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _read() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _readError = null;
    });
    try {
      final source = await widget.load();
      final data = await source.query.read(_month);
      final categories = await source.categories();
      if (!mounted || request != _request) return;
      _subscription ??= source.query.invalidation.changes.listen((_) {
        if (!busy) _read();
      });
      setState(() {
        _data = data;
        _categories = categories;
        if (_draft == null) _identity = source.identity;
      });
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _data = null;
          _readError = budgetError(e);
        });
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _clear() {
    setState(() {
      _draft = null;
      _error = null;
    });
  }

  Future<void> _begin(MonthlyBudgetRow row) async {
    if (locked || !await discard() || !mounted) return;
    setState(() {
      _draft = row;
      _amount.text = row.ownAmountCents == null
          ? ''
          : budgetDecimal(row.ownAmountCents!);
      _error = null;
    });
    _amountFocus.requestFocus();
  }

  Future<void> _save() async {
    if (locked || _draft == null) return;
    final row = _draft!;
    setState(() {
      busy = true;
      _error = null;
    });
    try {
      final amount = parseBudgetAmount(_amount.text);
      final source = await widget.load();
      if (!identical(source.identity, _identity)) {
        throw const BudgetFailure(
          'La base local se ha sustituido. Conserva tu borrador y vuelve a abrir el mes antes de escribir.',
        );
      }
      final old = row.budget;
      if (old == null) {
        await source.management.create(
          month: _month,
          categoryId: row.categoryId,
          amountCents: amount,
        );
      } else {
        await source.management.edit(old.id, amountCents: amount);
      }
      if (!mounted) return;
      _clear();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Partida guardada')));
      await _read();
    } catch (e) {
      if (mounted) {
        setState(() => _error = budgetError(e));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            (_draft == null ? _cellFocus[row.categoryId] : _amountFocus)
                ?.requestFocus();
          }
        });
      }
    }
  }

  Future<void> _open(MonthlyBudgetRow? row) async {
    if (locked || !await discard() || !mounted) return;
    final focus = FocusManager.instance.primaryFocus;
    _clear();
    await widget.onOpen(row, _month);
    if (!mounted) return;
    await _read();
    if (focus?.context != null) focus?.requestFocus();
  }

  Future<bool> _change(BudgetMonth month) async {
    if (locked || !await discard() || !mounted) {
      _year.text = _month.value.substring(0, 4);
      return false;
    }
    _clear();
    setState(() {
      _month = month;
      _year.text = month.value.substring(0, 4);
    });
    // La sesión publica el periodo aceptado también durante la carga.
    unawaited(_read());
    return true;
  }

  Future<void> _navigate(String path) async {
    if (locked || !await discard() || !mounted) return;
    _clear();
    widget.onNavigate(path, _month);
  }

  BigInt? _subtotal(MonthlyBudgetRow root) {
    BigInt? total;
    final parents = {for (final c in _categories) c.node.id: c.node.parentId};
    for (final row in [..._data!.activeTree, ..._data!.archivedBudgets]) {
      if (row.ownAmountCents == null) continue;
      String? id = row.categoryId;
      while (id != null) {
        if (id == root.categoryId) {
          total = (total ?? BigInt.zero) + BigInt.from(row.ownAmountCents!);
          break;
        }
        id = parents[id];
      }
    }
    return total;
  }

  Widget _own(MonthlyBudgetRow row, bool compact) {
    if (_draft?.categoryId == row.categoryId) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('budget-cell-input'),
            controller: _amount,
            focusNode: _amountFocus,
            enabled: !locked,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(
              labelText: 'Importe propio (€)',
              helperText: 'Signo + o −; cero válido. Intro confirma.',
            ),
            keyboardType: const TextInputType.numberWithOptions(
              signed: true,
              decimal: true,
            ),
          ),
          if (_error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: locked ? null : _save,
                child: Text(
                  busy
                      ? 'Guardando partida…'
                      : _error == null
                      ? 'Confirmar celda'
                      : 'Reintentar',
                ),
              ),
              TextButton(
                onPressed: locked
                    ? null
                    : () async {
                        if (await discard() && mounted) {
                          _clear();
                          _cellFocus[row.categoryId]?.requestFocus();
                        }
                      },
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ],
      );
    }
    return TextButton(
      focusNode: _cellFocus.putIfAbsent(row.categoryId, FocusNode.new),
      onPressed: locked ? null : () => compact ? _open(row) : _begin(row),
      child: Semantics(
        label:
            'Importe propio de ${row.category.path}, ${_month.value.substring(0, 7)}',
        child: Text(budgetEuro(row.ownAmountCents)),
      ),
    );
  }

  Widget _row(MonthlyBudgetRow row, bool compact) {
    final category = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(row.category.path),
        Text(
          row.category.node.isIncome ? 'Ingreso' : 'Salida',
          style: const TextStyle(fontSize: 14),
        ),
      ],
    );
    final detail = TextButton(
      onPressed: locked ? null : () => _open(row),
      child: Text('Abrir ${row.budget == null ? 'alta' : 'detalle'}'),
    );
    final subtotal = Semantics(
      label: 'Subtotal de rama de ${row.category.path}, solo lectura',
      child: Text('Subtotal de rama: ${budgetTotal(_subtotal(row))}'),
    );
    return Container(
      key: ValueKey(row.categoryId),
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [category, _own(row, true), subtotal, detail],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: (row.category.node.depth - 1) * 16,
                    ),
                    child: category,
                  ),
                ),
                Expanded(flex: 3, child: _own(row, false)),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [subtotal, detail],
                  ),
                ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 840;
    Widget navigation(bool vertical) => Wrap(
      direction: vertical ? Axis.vertical : Axis.horizontal,
      children: [
        for (final d in widget.destinations.entries)
          SizedBox(
            width: vertical ? 168 : (width - 32) / 2,
            child: Semantics(
              selected: d.key == '/presupuesto',
              child: TextButton(
                onPressed: locked ? null : () => _navigate(d.key),
                child: Text(d.value),
              ),
            ),
          ),
      ],
    );
    return PopScope(
      canPop: allowPop || (!dirty && !locked),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) leave(() => Navigator.of(context).pop());
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () async {
            if (!locked && await discard() && mounted) {
              final id = _draft?.categoryId;
              _clear();
              _cellFocus[id]?.requestFocus();
            }
          },
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Presupuesto mensual'),
            actions: [
              widget.management(_month, _read, () async {
                if (locked || !await discard() || !mounted) return false;
                _clear();
                return true;
              }),
            ],
          ),
          bottomNavigationBar: compact
              ? SafeArea(child: navigation(false))
              : null,
          body: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: compact ? 0 : (width >= 1200 ? 216 : 200),
                  child: compact ? null : navigation(true),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: EdgeInsets.all(
                      compact
                          ? 16
                          : width >= 1200
                          ? 32
                          : 24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (widget.periodControls != null)
                              widget.periodControls!(_month, _change)
                            else ...[
                              SizedBox(
                                width: 120,
                                child: TextField(
                                  controller: _year,
                                  enabled: !locked,
                                  decoration: const InputDecoration(
                                    labelText: 'Año',
                                  ),
                                  keyboardType: TextInputType.number,
                                  onSubmitted: (value) {
                                    try {
                                      _change(
                                        BudgetMonth(
                                          int.parse(value),
                                          int.parse(
                                            _month.value.substring(5, 7),
                                          ),
                                        ),
                                      );
                                    } catch (_) {
                                      _year.text = _month.value.substring(0, 4);
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Año inválido: usa 1 a 9999.',
                                              ),
                                            ),
                                          );
                                    }
                                  },
                                ),
                              ),
                              SizedBox(
                                width: compact ? width - 32 : 240,
                                child: DropdownButton<int>(
                                  isExpanded: true,
                                  value: int.parse(
                                    _month.value.substring(5, 7),
                                  ),
                                  items: [
                                    for (var m = 1; m <= 12; m++)
                                      DropdownMenuItem(
                                        value: m,
                                        child: Text(
                                          const [
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
                                          ][m - 1],
                                        ),
                                      ),
                                  ],
                                  onChanged: locked
                                      ? null
                                      : (m) => _change(
                                          BudgetMonth(
                                            int.parse(
                                              _month.value.substring(0, 4),
                                            ),
                                            m!,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                            FilledButton(
                              onPressed:
                                  locked || _loading || _readError != null
                                  ? null
                                  : () => _open(null),
                              child: const Text('Crear partida'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Cada confirmación guarda solo una partida. El subtotal de rama es de solo lectura.',
                        ),
                        if (_loading)
                          Semantics(
                            liveRegion: true,
                            child: Text('Consultando presupuesto…'),
                          )
                        else if (_readError != null) ...[
                          Semantics(liveRegion: true, child: Text(_readError!)),
                          TextButton(
                            onPressed: _read,
                            child: const Text('Reintentar'),
                          ),
                        ] else if (_data != null) ...[
                          if (!compact)
                            const Padding(
                              padding: EdgeInsets.all(10),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      'Categoría',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      'Importe propio · editable',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'Subtotal de rama · solo lectura',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (_data!.activeTree.isEmpty)
                            const Text(
                              'No hay categorías activas. Usa Gestión → Categorías.',
                            ),
                          for (final row in _data!.activeTree)
                            _row(row, compact),
                          if (_data!.archivedBudgets.isNotEmpty) ...[
                            const Text(
                              'Histórico archivado · incluido en el total',
                            ),
                            for (final row in _data!.archivedBudgets)
                              _row(row, true),
                          ],
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              'Total mensual: ${budgetTotal([..._data!.activeTree, ..._data!.archivedBudgets].where((r) => r.budget != null).isEmpty ? null : [..._data!.activeTree, ..._data!.archivedBudgets].fold<BigInt>(BigInt.zero, (n, r) => n + BigInt.from(r.ownAmountCents ?? 0)))}',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
