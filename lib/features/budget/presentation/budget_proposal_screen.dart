import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/autofinance_ui.dart';
import '../domain/budget_proposal.dart';
import '../domain/budget_proposal_editor.dart';
import '../domain/budget_proposal_saver.dart';
import '../domain/budget_repository.dart';
import 'budget_source.dart';
import 'budget_ui.dart';
import 'proposal_dialogs.dart';

const proposalMonths = [
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

class BudgetProposalScreen extends StatefulWidget {
  const BudgetProposalScreen({
    super.key,
    required this.load,
    required this.sourceYear,
    required this.onReturn,
  });
  final BudgetLoader load;
  final int sourceYear;
  final void Function(int year, bool saved) onReturn;
  @override
  State<BudgetProposalScreen> createState() => _BudgetProposalScreenState();
}

class _BudgetProposalScreenState
    extends BudgetDraftState<BudgetProposalScreen> {
  final _year = TextEditingController();
  final _yearFocus = FocusNode();
  final _signFocus = FocusNode();
  BudgetProposalEditor? _editor;
  BudgetSource? _source;
  String? _error;
  bool _stale = false;
  bool _showDetail = false;
  int _reviewMonth = 1;
  final _monthReview = GlobalKey();
  final _cellFocus = <String, FocusNode>{};
  late int _returnYear;
  @override
  bool get dirty => _editor != null;
  @override
  void initState() {
    super.initState();
    _returnYear = widget.sourceYear;
    _year.text = widget.sourceYear.toString();
  }

  @override
  void dispose() {
    _editor?.cancel();
    _year.dispose();
    _yearFocus.dispose();
    _signFocus.dispose();
    for (final node in _cellFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  String _message(Object error) => switch (error) {
    BudgetProposalFailure() => error.message,
    BudgetProposalEditFailure() => error.message,
    BudgetProposalSaveFailure() => error.message,
    _ => budgetError(error),
  };

  Future<void> _generate() async {
    if (locked) return;
    final year = int.tryParse(_year.text.trim());
    if (year == null || year < 1 || year > 9998) {
      setState(() => _error = 'Elige un año fuente entre 1 y 9998.');
      _yearFocus.requestFocus();
      return;
    }
    if (_editor != null &&
        !await ask(
          'Regenerar propuesta',
          'Un cálculo nuevo sustituirá este borrador y sus ediciones manuales. '
              'Si falla la lectura, conservarás el borrador actual.',
          'Regenerar y descartar ediciones',
          cancel: 'Conservar borrador',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      busy = true;
      _error = null;
    });
    try {
      final source = await widget.load();
      final calculator = source.proposalCalculator;
      if (calculator == null || source.proposalSaver == null) {
        throw const BudgetFailure(
          'La propuesta no está disponible en esta base.',
        );
      }
      final draft = await calculator.calculate(year);
      if (!mounted) return;
      final editor = BudgetProposalEditor(draft);
      _editor?.cancel();
      setState(() {
        _editor = editor;
        _source = source;
        _returnYear = year;
        _stale = false;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _checkIdentity() async {
    final current = await widget.load();
    if (!identical(current.identity, _source!.identity)) {
      throw const BudgetProposalSaveFailure(
        'La base local se ha sustituido. El borrador se conserva. '
        'Regenera y revisa la propuesta antes de guardar.',
        code: BudgetProposalSaveFailureCode.staleReview,
      );
    }
  }

  Future<T?> _dialog<T>(Widget child) async {
    final focus = FocusManager.instance.primaryFocus;
    setState(() => confirming = true);
    final route = DialogRoute<T>(
      context: context,
      builder: (context) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.pop(context),
        },
        child: child,
      ),
    );
    try {
      final result = await Navigator.of(context).push(route);
      await route.completed;
      return result;
    } finally {
      if (mounted) {
        setState(() => confirming = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && focus?.context != null) focus?.requestFocus();
        });
      }
    }
  }

  Future<void> _edit(BudgetInput item, {required bool split}) async {
    if (locked) return;
    final editor = _editor!;
    final category = editor.draft.basis.categories.firstWhere(
      (c) => c.node.id == item.categoryId,
    );
    final changed = await _dialog<bool>(
      ProposalAllocationDialog(
        editor: editor,
        item: item,
        categoryPath: category.path,
        split: split,
      ),
    );
    if (mounted && changed == true) setState(() => _error = null);
  }

  Future<void> _save() async {
    if (locked || _editor == null || _stale) return;
    if (_editor!.draft.includedScopes.isEmpty) return;
    setState(() {
      busy = true;
      _error = null;
    });
    try {
      final draft = _editor!.validatedDraft();
      await _checkIdentity();
      final saver = _source!.proposalSaver!;
      final review = await saver.review(draft);
      if (!mounted) return;
      setState(() => busy = false);
      final confirmed = await _dialog<bool>(
        ProposalComparisonDialog(review: review),
      );
      if (!mounted || confirmed != true) return;
      setState(() => busy = true);
      await _checkIdentity();
      await saver.save(review, confirmation: review.requiredConfirmation);
      _source!.query.invalidation.invalidate();
      if (!mounted) return;
      setState(() {
        busy = false;
        allowPop = true;
      });
      widget.onReturn(draft.targetYear, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _message(error);
          if (error is BudgetProposalSaveFailure &&
              error.code == BudgetProposalSaveFailureCode.staleReview) {
            _stale = true;
          }
          if (error is BudgetProposalEditFailure &&
              error.code == BudgetProposalEditFailureCode.signsNotReviewed) {
            _signFocus.requestFocus();
          }
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _cancel() => leave(() => widget.onReturn(_returnYear, false));
  void _viewTarget() =>
      leave(() => widget.onReturn(_editor!.draft.targetYear, false));

  List<BudgetInput> _allocations(BudgetProposalRow row) {
    final categories = {
      for (final c in _editor!.draft.basis.categories) c.node.id: c,
    };
    bool belongs(String id) {
      String? current = id;
      while (current != null) {
        if (current == row.categoryId) return true;
        current = categories[current]?.node.parentId;
      }
      return false;
    }

    return _editor!.draft.allocations
        .where(
          (a) =>
              a.month.value == row.targetMonth.value && belongs(a.categoryId),
        )
        .toList();
  }

  BigInt _total(Iterable<BudgetInput> items) =>
      items.fold(BigInt.zero, (sum, a) => sum + BigInt.from(a.amountCents));

  String _proposalAmount(int cents) =>
      '${budgetTotal(BigInt.from(cents))}${cents == 0 ? ' (cero explícito)' : ''}';

  Widget _month(BudgetProposalRow row) {
    final items = _allocations(row);
    final categories = {
      for (final c in _editor!.draft.basis.categories) c.node.id: c,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Real fuente: ${row.hasSourceReals ? budgetTotal(BigInt.from(row.sourceAmountCents)) : 'Sin reales (0,00 €)'}',
        ),
        if (!row.hasSourceReals) const Text('Sin reales · cero explícito'),
        Text('Propuesto inicial: ${_proposalAmount(row.proposedAmountCents)}'),
        if (row.requiresSignReview) const Text('Revisar signo del real fuente'),
        for (final item in items) ...[
          Text(
            '${categories[item.categoryId]!.path}: ${_proposalAmount(item.amountCents)}',
          ),
          if (_editor!.draft.signWarnings.any(
            (w) =>
                w.origin == BudgetProposalSignOrigin.allocation &&
                w.categoryId == item.categoryId &&
                w.month.value == item.month.value,
          ))
            const Text('Revisar signo de la partida'),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                key: ValueKey('edit-${item.categoryId}-${item.month.value}'),
                onPressed: locked ? null : () => _edit(item, split: false),
                child: Semantics(
                  label:
                      'Editar partida ${categories[item.categoryId]!.path}, ${item.month.value.substring(0, 7)}',
                  child: const ExcludeSemantics(child: Text('Editar')),
                ),
              ),
              if (_editor!
                  .splitOptions(
                    month: item.month,
                    parentCategoryId: item.categoryId,
                  )
                  .isNotEmpty)
                TextButton(
                  key: ValueKey('split-${item.categoryId}-${item.month.value}'),
                  onPressed: locked ? null : () => _edit(item, split: true),
                  child: Semantics(
                    label:
                        'Desglosar partida ${categories[item.categoryId]!.path}, ${item.month.value.substring(0, 7)}',
                    child: const ExcludeSemantics(child: Text('Desglosar')),
                  ),
                ),
            ],
          ),
        ],
        Text('Total del borrador: ${budgetTotal(_total(items))}'),
      ],
    );
  }

  Widget _monthlyReview() {
    final draft = _editor!.draft;
    final roots = {
      for (final row in draft.sourceRows) row.categoryId: row.root,
    };
    return AfResponsiveGrid(
      columns: 2,
      children: [
        for (final root in roots.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: AfCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  Text(
                    root.path,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(root.node.isIncome ? 'Ingreso' : 'Salida'),
                  for (final row in draft.sourceRows.where(
                    (r) =>
                        r.categoryId == root.node.id &&
                        int.parse(r.targetMonth.value.substring(5, 7)) ==
                            _reviewMonth,
                  ))
                    _month(row),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _selectMonth(int month) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _reviewMonth = month);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _monthReview.currentContext != null) {
        Scrollable.ensureVisible(_monthReview.currentContext!);
      }
    });
  }

  Widget _proposalCell(BudgetProposalRow row) {
    final token = 'proposal-cell-${row.categoryId}-${row.targetMonth.value}';
    final focus = _cellFocus.putIfAbsent(token, FocusNode.new);
    final amount = budgetTotal(_total(_allocations(row)));
    return Builder(
      builder: (cellContext) => Focus(
        onFocusChange: (focused) {
          if (!focused) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (cellContext.mounted && focus.hasFocus) {
              // La etiqueta fija no debe cubrir una celda enfocada por Tab.
              Scrollable.ensureVisible(cellContext, alignment: 1);
            }
          });
        },
        canRequestFocus: false,
        child: TextButton(
          key: ValueKey(token),
          focusNode: focus,
          onPressed: locked
              ? null
              : () => _selectMonth(
                  int.parse(row.targetMonth.value.substring(5, 7)),
                ),
          child: Semantics(
            label:
                'Borrador ${row.root.path}, ${row.targetMonth.value.substring(0, 7)}, $amount. Revisar partidas',
            child: ExcludeSemantics(child: AfNumericText(amount)),
          ),
        ),
      ),
    );
  }

  Widget _annualDetail(bool compact) {
    final draft = _editor!.draft;
    final roots = {
      for (final row in draft.sourceRows) row.categoryId: row.root,
    };
    if (compact) {
      return AfCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Todos los meses del destino'),
            for (var m = 1; m <= 12; m++)
              AfValueRow(
                label: '${proposalMonths[m - 1]} ${draft.targetYear}',
                value: AfNumericText(
                  budgetTotal(
                    _total(
                      draft.allocations.where(
                        (a) => int.parse(a.month.value.substring(5, 7)) == m,
                      ),
                    ),
                  ),
                ),
                onPressed: locked ? null : () => _selectMonth(m),
              ),
          ],
        ),
      );
    }
    return AfDetailTable(
      caption:
          'Borrador ${draft.targetYear} · Pulsa una cifra para revisar y editar sus partidas',
      columns: [...proposalMonths, 'Total anual'],
      cellWidth: 170,
      rows: [
        for (final root in roots.values)
          AfDetailRow(
            label: root.path,
            values: [
              for (final row in draft.sourceRows.where(
                (r) => r.categoryId == root.node.id,
              ))
                _proposalCell(row),
              AfNumericText(
                budgetTotal(
                  _total([
                    for (final row in draft.sourceRows.where(
                      (r) => r.categoryId == root.node.id,
                    ))
                      ..._allocations(row),
                  ]),
                ),
              ),
            ],
          ),
        AfDetailRow(
          label: 'Total mensual · solo raíces',
          total: true,
          values: [
            for (var m = 1; m <= 12; m++)
              AfNumericText(
                budgetTotal(
                  _total(
                    draft.allocations.where(
                      (a) => int.parse(a.month.value.substring(5, 7)) == m,
                    ),
                  ),
                ),
              ),
            AfNumericText(budgetTotal(_total(draft.allocations))),
          ],
        ),
      ],
    );
  }

  Widget _summary() {
    final draft = _editor!.draft;
    final source = draft.sourceRows.fold(
      BigInt.zero,
      (n, row) => n + BigInt.from(row.sourceAmountCents),
    );
    return AfResponsiveGrid(
      columns: 2,
      children: [
        AfCard(
          tone: AfCardTone.real,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Text('Real de origen · ${draft.sourceYear}'),
              Text(
                budgetTotal(source),
                style:
                    (AfTokens.reflow(context, MediaQuery.sizeOf(context).width)
                            ? Theme.of(context).textTheme.bodyLarge
                            : Theme.of(context).textTheme.headlineMedium)
                        ?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
              ),
              const Text('Raíces incluidas · Suma de los meses equivalentes'),
            ],
          ),
        ),
        AfCard(
          tone: AfCardTone.budget,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Text('Borrador · ${draft.targetYear}'),
              Text(
                budgetTotal(_total(draft.allocations)),
                style:
                    (AfTokens.reflow(context, MediaQuery.sizeOf(context).width)
                            ? Theme.of(context).textTheme.bodyLarge
                            : Theme.of(context).textTheme.headlineMedium)
                        ?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
              ),
              Text(
                '${draft.allocations.length} partidas · Incluye tus ediciones · Pendiente de guardar',
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = _editor?.draft;
    final compact =
        Theme.of(context).platform == TargetPlatform.android ||
        MediaQuery.sizeOf(context).width < 840 ||
        MediaQuery.textScalerOf(context).scale(16) >= 24;
    return PopScope(
      canPop: allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _cancel();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _cancel,
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              draft == null ? _generate : _save,
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Propuesta'),
            automaticallyImplyLeading: false,
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextButton(
                    onPressed: locked ? null : _cancel,
                    child: Text('Volver a Presupuesto, $_returnYear'),
                  ),
                  Text(
                    'Propuesta para un año nuevo',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const Text(
                    'Borrador solo de esta sesión. Ninguna partida cambia hasta confirmar el guardado.',
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 180,
                        child: TextField(
                          key: const ValueKey('proposal-year'),
                          controller: _year,
                          focusNode: _yearFocus,
                          enabled: !locked,
                          decoration: const InputDecoration(
                            labelText: 'Año fuente (1–9998)',
                          ),
                          keyboardType: TextInputType.number,
                          onSubmitted: (_) => _generate(),
                        ),
                      ),
                      FilledButton(
                        onPressed: locked ? null : _generate,
                        child: Text(
                          draft == null
                              ? 'Generar propuesta'
                              : 'Regenerar propuesta',
                        ),
                      ),
                    ],
                  ),
                  if (busy)
                    const AfStatus(
                      kind: AfStatusKind.loading,
                      message: 'Calculando o comprobando el guardado…',
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  if (_stale)
                    const Text(
                      'Datos obsoletos. El borrador y sus ediciones se conservan. Regenera expresamente y revisa de nuevo antes de guardar.',
                    ),
                  if (draft != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Fuente: ${draft.sourceYear} · Destino: ${draft.targetYear}',
                    ),
                    const Text(
                      'Suma algebraica de reales por raíz y mes; magnitud redondeada a la decena superior o igual, conservando el signo. Editar no recalcula los demás meses.',
                    ),
                    TextButton(
                      onPressed: locked ? null : _viewTarget,
                      child: const Text('Ver año destino existente'),
                    ),
                    if (draft.sourceRows.isEmpty)
                      const Text(
                        'No hay raíces activas para proponer. No se inventan partidas.',
                      ),
                    const SizedBox(height: 24),
                    _summary(),
                    const SizedBox(height: 24),
                    AfPageHeader(
                      title: 'Revisar y editar',
                      actions: [
                        AfAction(
                          key: const Key('proposal-show-detail'),
                          label: _showDetail
                              ? 'Ocultar detalle anual'
                              : 'Ver detalle',
                          onPressed: locked
                              ? null
                              : () =>
                                    setState(() => _showDetail = !_showDetail),
                        ),
                      ],
                    ),
                    if (_showDetail) ...[
                      _annualDetail(compact),
                      const SizedBox(height: 24),
                    ],
                    SizedBox(
                      key: _monthReview,
                      width: 300,
                      child: AfPeriodSelector(
                        key: ValueKey('proposal-review-month-$_reviewMonth'),
                        label: 'Mes de revisión · ${draft.targetYear}',
                        options: [
                          for (var m = 1; m <= 12; m++)
                            AfPeriodOption(
                              id: '$m',
                              label: proposalMonths[m - 1],
                            ),
                        ],
                        selectedId: '$_reviewMonth',
                        onChanged: locked
                            ? null
                            : (value) => setState(
                                () => _reviewMonth = int.parse(value),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _monthlyReview(),
                    Text(
                      'Total anual del borrador: ${budgetTotal(_total(draft.allocations))}',
                    ),
                    if (draft.excludedReals.isNotEmpty)
                      ExpansionTile(
                        title: Text(
                          'Reales excluidos (${draft.excludedReals.length}) · aviso no bloqueante',
                        ),
                        children: [
                          for (final excluded in draft.excludedReals)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                '${excluded.real.valueDate} · ${excluded.reason == BudgetProposalExclusionReason.unclassified ? 'Sin clasificar' : 'Raíz archivada: ${excluded.categoryPath}'} · ${budgetEuro(excluded.real.amountCents)}',
                              ),
                            ),
                        ],
                      ),
                    if (draft.requiresSignReview) ...[
                      const Text('Signos atípicos · revisión obligatoria'),
                      for (final warning in draft.signWarnings)
                        Text(
                          '${warning.origin == BudgetProposalSignOrigin.sourceReal ? 'Real fuente' : 'Partida'} · ${warning.categoryPath} · ${warning.month.value.substring(0, 7)} · ${budgetEuro(warning.amountCents)}',
                        ),
                      CheckboxListTile(
                        focusNode: _signFocus,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('He revisado los signos señalados'),
                        value: draft.signsReviewed,
                        onChanged: locked
                            ? null
                            : (value) => setState(
                                () => _editor!.setSignsReviewed(value ?? false),
                              ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton(
                          onPressed:
                              locked || _stale || draft.includedScopes.isEmpty
                              ? null
                              : _save,
                          child: const Text('Revisar y guardar'),
                        ),
                        TextButton(
                          onPressed: locked ? null : _cancel,
                          child: const Text('Cancelar propuesta'),
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
}
