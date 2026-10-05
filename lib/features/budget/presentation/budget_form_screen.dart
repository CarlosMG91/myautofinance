import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/budget_repository.dart';
import '../../movements/movements.dart';
import 'budget_source.dart';
import 'budget_ui.dart';

class BudgetFormScreen extends StatefulWidget {
  const BudgetFormScreen({
    super.key,
    required this.load,
    required this.month,
    required this.onReturn,
    required this.onSaved,
    required this.onDeleted,
    required this.selectCategory,
    this.id,
    this.categoryId,
    this.destinations = const {},
  });
  final BudgetLoader load;
  final BudgetMonth month;
  final String? id, categoryId;
  final VoidCallback onReturn, onDeleted;
  final ValueChanged<BudgetRecord> onSaved;
  final Future<CategoryDetails?> Function(String?) selectCategory;
  final Map<String, VoidCallback> destinations;
  @override
  State<BudgetFormScreen> createState() => _BudgetFormScreenState();
}

class _BudgetFormScreenState extends BudgetDraftState<BudgetFormScreen> {
  final _period = TextEditingController(), _amount = TextEditingController();
  final _periodFocus = FocusNode(),
      _amountFocus = FocusNode(),
      _categoryFocus = FocusNode();
  BudgetRecord? _old;
  Object? _identity;
  CategoryDetails? _category;
  String? _error, _readError, _periodError, _amountError, _categoryError;
  bool _loading = true, _editing = false, _picking = false;
  @override
  bool get locked => super.locked || _picking;
  String get _initialPeriod =>
      (_old?.data.month ?? widget.month).value.substring(0, 7);
  @override
  bool get dirty =>
      _editing &&
      (_period.text != _initialPeriod ||
          _amount.text !=
              (_old == null ? '' : budgetDecimal(_old!.data.amountCents)) ||
          _category?.node.id != (_old?.data.categoryId ?? widget.categoryId));
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_period, _amount]) {
      c.dispose();
    }
    for (final f in [_periodFocus, _amountFocus, _categoryFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _readError = null;
    });
    try {
      final source = await widget.load();
      final old = widget.id == null
          ? null
          : await source.management.get(widget.id!);
      final categories = await source.categories();
      if (!mounted) return;
      setState(() {
        _identity = source.identity;
        _old = old;
        _editing = old == null;
        final id = old?.data.categoryId ?? widget.categoryId;
        _category = categories.where((c) => c.node.id == id).firstOrNull;
        _period.text = _initialPeriod;
        _amount.text = old == null ? '' : budgetDecimal(old.data.amountCents);
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _readError = 'No se pudo abrir este detalle. ${budgetError(e)}',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<BudgetSource> _source() async {
    final source = await widget.load();
    if (!identical(source.identity, _identity)) {
      throw const BudgetFailure(
        'La base local se ha sustituido. El borrador se conserva; vuelve a abrir la partida antes de escribir.',
      );
    }
    return source;
  }

  Future<void> _pick() async {
    if (locked) return;
    setState(() => _picking = true);
    try {
      final selected = await widget.selectCategory(_category?.node.id);
      if (mounted && selected != null) {
        setState(() {
          _category = selected;
          _categoryError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = budgetError(e));
    } finally {
      if (mounted) {
        setState(() => _picking = false);
        _categoryFocus.requestFocus();
      }
    }
  }

  Future<void> _save() async {
    if (locked) return;
    BudgetMonth? month;
    int? amount;
    setState(() {
      _periodError = _amountError = _categoryError = null;
      try {
        month = BudgetMonth.parse('${_period.text.trim()}-01');
      } catch (_) {
        _periodError = 'Usa un mes válido AAAA-MM.';
      }
      try {
        amount = parseBudgetAmount(_amount.text);
      } catch (e) {
        _amountError = budgetError(e);
      }
      if (_category == null) _categoryError = 'Selecciona una categoría.';
    });
    if (month == null || amount == null || _category == null) {
      final focus = month == null
          ? _periodFocus
          : _category == null
          ? _categoryFocus
          : _amountFocus;
      focus.requestFocus();
      if (focus.context != null) await Scrollable.ensureVisible(focus.context!);
      return;
    }
    setState(() {
      busy = true;
      _error = null;
    });
    try {
      final source = await _source();
      final saved = _old == null
          ? await source.management.create(
              month: month!,
              categoryId: _category!.node.id,
              amountCents: amount!,
            )
          : await source.management.edit(
              _old!.id,
              month: month,
              categoryId: _category!.node.id,
              amountCents: amount,
            );
      if (!mounted) return;
      // La escritura ya está confirmada: nunca repetir un alta tras un fallo de lectura.
      setState(() {
        _old = saved;
        _editing = false;
      });
      busy = false;
      await leave(() => widget.onSaved(saved));
    } catch (e) {
      if (mounted) setState(() => _error = budgetError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _delete() async {
    if (locked || _old == null) return;
    if (!await ask(
          'Eliminar partida',
          '${_old!.data.month.value.substring(0, 7)} · ${_category?.path}\n${budgetEuro(_old!.data.amountCents)}\nEl mes quedará sin presupuesto en esta categoría.',
          'Eliminar partida',
        ) ||
        !mounted) {
      return;
    }
    setState(() {
      busy = true;
      _error = null;
    });
    try {
      await (await _source()).management.delete(_old!.id);
      if (!mounted) return;
      setState(() => _editing = false);
      busy = false;
      await leave(widget.onDeleted);
    } catch (e) {
      if (mounted) setState(() => _error = budgetError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) leave(widget.onReturn);
    },
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            leave(widget.onReturn),
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.id == null ? 'Crear partida' : 'Detalle de partida',
          ),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextButton(
                      onPressed: locked ? null : () => leave(widget.onReturn),
                      child: Text(
                        'Volver a Presupuesto, ${widget.month.value.substring(0, 7)}',
                      ),
                    ),
                    if (_loading)
                      const Text('Leyendo partida…')
                    else if (_readError != null) ...[
                      Semantics(liveRegion: true, child: Text(_readError!)),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Reintentar'),
                      ),
                    ] else ...[
                      const Text(
                        'Año/mes → categoría → importe firmado. Cero registra una partida. No tiene cuenta.',
                      ),
                      TextField(
                        key: const Key('budget-period'),
                        controller: _period,
                        focusNode: _periodFocus,
                        enabled: _editing && !locked,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Año/mes (AAAA-MM)',
                          errorText: _periodError,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Categoría: ${_category?.path ?? 'Sin seleccionar'}${_category?.node.archived == true ? ' · Archivada (se puede conservar)' : ''}',
                      ),
                      if (_category != null)
                        Text(
                          _category!.node.isIncome
                              ? 'Ingreso heredado de la raíz'
                              : 'Salida heredada de la raíz',
                        ),
                      if (_editing)
                        OutlinedButton(
                          focusNode: _categoryFocus,
                          onPressed: locked ? null : _pick,
                          child: const Text('Seleccionar categoría'),
                        ),
                      if (_categoryError != null)
                        Semantics(
                          liveRegion: true,
                          child: Text(_categoryError!),
                        ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const Key('budget-form-amount'),
                        controller: _amount,
                        focusNode: _amountFocus,
                        enabled: _editing && !locked,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _save(),
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Importe firmado (€)',
                          helperText: 'Coma o punto; hasta dos decimales. Vaciar no elimina.',
                          errorText: _amountError,
                        ),
                      ),
                      if (_old != null) ...[
                        const SizedBox(height: 16),
                        const Text('Metadatos históricos · solo lectura'),
                        Text(
                          'ID: ${_old!.id}\nConcepto: ${_old!.data.concept ?? 'Sin dato'}\nDiscrecionalidad: ${_old!.data.discretion ?? 'Sin dato'}\nLote CSV: ${_old!.batchId ?? 'Sin dato'}\nFila de origen: ${_old!.importRowId ?? 'Sin dato'}\nOrdinal CSV: ${_old!.sourceOrdinal ?? 'Sin dato'}',
                        ),
                      ],
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
                      if (busy)
                        Semantics(
                          liveRegion: true,
                          child: Text('Persistiendo partida…'),
                        ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          TextButton(
                            onPressed: locked
                                ? null
                                : () => leave(widget.onReturn),
                            child: const Text('Cancelar'),
                          ),
                          if (!_editing)
                            FilledButton(
                              onPressed: locked
                                  ? null
                                  : () {
                                      setState(() => _editing = true);
                                      _periodFocus.requestFocus();
                                    },
                              child: const Text('Editar'),
                            )
                          else
                            FilledButton(
                              onPressed: locked ? null : _save,
                              child: Text(
                                _error == null
                                    ? 'Guardar partida'
                                    : 'Reintentar',
                              ),
                            ),
                          if (_old != null)
                            OutlinedButton(
                              onPressed: locked ? null : _delete,
                              child: const Text('Eliminar partida'),
                            ),
                        ],
                      ),
                    ],
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final d in widget.destinations.entries)
                          TextButton(
                            onPressed: locked ? null : () => leave(d.value),
                            child: Text(d.key),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
