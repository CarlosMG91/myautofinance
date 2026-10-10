import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/budget_proposal_editor.dart';
import '../domain/budget_proposal_saver.dart';
import '../domain/budget_repository.dart';
import '../../movements/movements.dart' show CategoryDetails;
import 'budget_ui.dart';

Widget _title(String text) =>
    Focus(autofocus: true, child: Semantics(header: true, child: Text(text)));

class ProposalAllocationDialog extends StatefulWidget {
  const ProposalAllocationDialog({
    super.key,
    required this.editor,
    required this.item,
    required this.categoryPath,
    required this.split,
  });
  final BudgetProposalEditor editor;
  final BudgetInput item;
  final String categoryPath;
  final bool split;
  @override
  State<ProposalAllocationDialog> createState() =>
      _ProposalAllocationDialogState();
}

class _ProposalAllocationDialogState extends State<ProposalAllocationDialog> {
  final _amount = TextEditingController();
  final _amountFocus = FocusNode();
  final _children = <String, TextEditingController>{};
  final _focus = <String, FocusNode>{};
  final _selected = <String>{};
  List<CategoryDetails> _options = [];
  bool _editTotal = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _amount.text = budgetDecimal(widget.item.amountCents);
    if (widget.split) {
      _options = widget.editor.splitOptions(
        month: widget.item.month,
        parentCategoryId: widget.item.categoryId,
      );
      for (final c in _options) {
        _children[c.node.id] = TextEditingController(text: '0,00');
        _focus[c.node.id] = FocusNode();
      }
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _amountFocus.dispose();
    for (final controller in _children.values) {
      controller.dispose();
    }
    for (final focus in _focus.values) {
      focus.dispose();
    }
    super.dispose();
  }

  Widget _field(
    TextEditingController controller,
    FocusNode focus,
    String label,
  ) => TextField(
    controller: controller,
    focusNode: focus,
    decoration: InputDecoration(
      labelText: label,
      helperText: 'EUR · + entrada, − salida; cero válido',
      helperMaxLines: 3,
    ),
    keyboardType: const TextInputType.numberWithOptions(
      decimal: true,
      signed: true,
    ),
    onSubmitted: (_) {
      if (!widget.split) _apply();
    },
  );

  int _parse(TextEditingController controller, FocusNode focus) {
    try {
      return parseBudgetAmount(controller.text);
    } catch (_) {
      focus.requestFocus();
      rethrow;
    }
  }

  void _apply() {
    try {
      if (widget.split) {
        widget.editor.split(
          month: widget.item.month,
          parentCategoryId: widget.item.categoryId,
          allocations: [
            for (final c in _options.where(
              (c) => _selected.contains(c.node.id),
            ))
              BudgetProposalSplitAllocation(
                categoryId: c.node.id,
                amountCents: _parse(_children[c.node.id]!, _focus[c.node.id]!),
              ),
          ],
          explicitlyEditedTotalCents: _editTotal
              ? _parse(_amount, _amountFocus)
              : null,
        );
      } else {
        widget.editor.editAmount(
          month: widget.item.month,
          categoryId: widget.item.categoryId,
          amountCents: _parse(_amount, _amountFocus),
        );
      }
      Navigator.pop(context, true);
    } catch (error) {
      setState(
        () => _error = error is BudgetProposalEditFailure
            ? error.message
            : budgetError(error),
      );
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.enter, control: true): _apply,
    },
    child: AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.all(16),
      title: _title(widget.split ? 'Desglosar partida' : 'Editar importe'),
      content: SizedBox(
        width: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.categoryPath} · ${widget.item.month.value.substring(0, 7)}',
            ),
            if (!widget.split)
              _field(_amount, _amountFocus, 'Importe propuesto')
            else ...[
              Text(
                'Total anterior: ${budgetEuro(widget.item.amountCents)}. El padre se retira solo de este mes. Elige descendientes activos; la suma debe conservar el total.',
              ),
              for (final c in _options) ...[
                CheckboxListTile(
                  key: ValueKey('split-option-${c.node.id}'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _selected.contains(c.node.id),
                  title: Text(
                    _options.where((other) => other.path == c.path).length > 1
                        ? '${c.path} (opción ${_options.indexOf(c) + 1})'
                        : c.path,
                  ),
                  onChanged: (value) => setState(() {
                    if (value == true) {
                      _selected.add(c.node.id);
                    } else {
                      _selected.remove(c.node.id);
                    }
                  }),
                ),
                if (_selected.contains(c.node.id))
                  _field(
                    _children[c.node.id]!,
                    _focus[c.node.id]!,
                    'Importe de ${c.path}',
                  ),
              ],
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _editTotal,
                title: const Text('Editar expresamente el total de este mes'),
                onChanged: (value) =>
                    setState(() => _editTotal = value ?? false),
              ),
              if (_editTotal)
                _field(_amount, _amountFocus, 'Nuevo total explícito'),
            ],
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _apply,
          child: Text(widget.split ? 'Aplicar desglose' : 'Aplicar importe'),
        ),
      ],
    ),
  );
}

class ProposalComparisonDialog extends StatefulWidget {
  const ProposalComparisonDialog({super.key, required this.review});
  final BudgetProposalReview review;
  @override
  State<ProposalComparisonDialog> createState() =>
      _ProposalComparisonDialogState();
}

class _ProposalComparisonDialogState extends State<ProposalComparisonDialog> {
  bool _confirmed = false;
  String _kind(BudgetProposalChangeKind kind) => switch (kind) {
    BudgetProposalChangeKind.added => 'Nueva',
    BudgetProposalChangeKind.updated => 'Corrección',
    BudgetProposalChangeKind.unchanged => 'Sin cambio',
    BudgetProposalChangeKind.removed => 'Retirada',
  };
  @override
  Widget build(BuildContext context) {
    final review = widget.review;
    final draft = review.plan.draft;
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.all(16),
      title: _title('Comparar propuesta ${draft.targetYear}'),
      content: SizedBox(
        width: 720,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${review.changes.length} partidas · ${draft.includedScopes.length} ámbitos de raíz y mes incluidos. Solo se sustituyen estos ámbitos; el año fuente ${draft.sourceYear}, fotos y reales se conservan.',
            ),
            for (final change in review.changes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${change.month.value.substring(0, 7)} · ${change.categoryPath} · ${_kind(change.kind)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Anterior: ${change.before == null ? 'Sin partida' : budgetEuro(change.before!.data.amountCents)}',
                    ),
                    Text(
                      'Nuevo: ${change.after == null ? 'Retirada · sin partida' : budgetEuro(change.after!.amountCents)}',
                    ),
                  ],
                ),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'He revisado la comparación y confirmo «${review.confirmationLabel}»',
              ),
              value: _confirmed,
              onChanged: (value) => setState(() => _confirmed = value ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _confirmed ? () => Navigator.pop(context, true) : null,
          child: Text(review.confirmationLabel),
        ),
      ],
    );
  }
}
