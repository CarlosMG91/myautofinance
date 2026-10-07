import 'package:flutter/material.dart';

import 'dart:ui' show AppExitResponse;

import '../importing.dart';
import 'import_controller.dart';
import 'import_reference_dialog.dart';
import 'import_widgets.dart';

class ImportReviewScreen extends StatefulWidget {
  const ImportReviewScreen({
    super.key,
    required this.controller,
    required this.onReturn,
    required this.onHistory,
    required this.onBatch,
    required this.onPeriod,
    this.returnLabel = 'Volver al origen',
  });
  final ImportController controller;
  final VoidCallback onReturn, onHistory;
  final void Function(String) onBatch;
  final void Function(String, String) onPeriod;
  final String returnLabel;
  @override
  State<ImportReviewScreen> createState() => _ImportReviewScreenState();
}

class _ImportReviewScreenState extends State<ImportReviewScreen>
    with WidgetsBindingObserver {
  int _page = 0;
  bool _dialog = false;
  ImportController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async =>
      await _allowLeave() ? AppExitResponse.exit : AppExitResponse.cancel;
  Future<bool> _allowLeave() async {
    if (c.phase == ImportPhase.confirming || _dialog) return false;
    if (c.hasSession) {
      _dialog = true;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Descartar la revisión?'),
          content: const Text(
            'Las decisiones sin confirmar se perderán. Los datos guardados se conservan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Seguir revisando'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Descartar sesión'),
            ),
          ],
        ),
      );
      _dialog = false;
      if (!mounted || discard != true || !c.discard()) return false;
    }
    return true;
  }

  Future<void> _leave() async {
    if (!await _allowLeave() || !mounted) return;
    widget.onReturn();
  }

  Future<void> _confirm() async {
    if (!c.canConfirm || _dialog) return;
    _dialog = true;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar el lote completo'),
        content: Text(
          '${c.review!.movementCount} reales y ${c.review!.budgetCount} presupuestos. '
          'Se guardarán en la base local junto a las referencias preparadas. No hay deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Seguir revisando'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Importar todo'),
          ),
        ],
      ),
    );
    _dialog = false;
    if (!mounted || approved != true) return;
    await c.confirm();
  }

  Future<void> _resolve(ImportReference reference) async {
    if (c.busy || c.result != null || _dialog || c.snapshot == null) return;
    _dialog = true;
    final decision = await chooseImportReference(
      context,
      reference,
      c.snapshot!,
      c.review!.bindings,
    );
    _dialog = false;
    if (!mounted || decision == null) return;
    _page = 0;
    switch (reference) {
      case PendingImportAccount(:final account):
        await c.bindAccount(
          account,
          id: decision is String ? decision : null,
          plan: decision is ImportNewAccount ? decision : null,
        );
      case PendingImportCategory(:final category):
        await c.bindCategory(
          category,
          id: decision is String ? decision : null,
          plan: decision is ImportNewCategory ? decision : null,
        );
    }
  }

  String _account(InterpretedMovement row) {
    final b = c.review!.bindings;
    final plan = b.newAccounts[row.account];
    if (plan != null) return '${plan.name} · alta preparada';
    final id = b.accounts[row.account];
    final matches = c.snapshot?.accounts.where((a) => a.id == id);
    return matches != null && matches.isNotEmpty
        ? matches.first.name
        : 'Pendiente: ${row.account.name ?? 'cuenta global'}';
  }

  String _category(ImportCategoryReference ref) {
    final b = c.review!.bindings;
    if (b.newCategories.containsKey(ref)) {
      return '${importPlannedCategoryPath(ref, b, c.snapshot?.categories ?? [])} · alta preparada';
    }
    final id = b.categories[ref];
    return id == null
        ? '${ref.path.join(' / ')} · pendiente'
        : importCategoryPath(id, c.snapshot?.categories ?? []);
  }

  String _rowStatus(InterpretedImportRow row) {
    if (c.review!.issues.any((i) => i.sourceOrdinal == row.sourceOrdinal)) {
      return 'Error';
    }
    if (!c.review!.bindings.resolves(row)) return 'Referencia pendiente';
    final overlaps = c.review!.overlaps.where(
      (o) => o.sourceOrdinal == row.sourceOrdinal,
    );
    if (overlaps.isNotEmpty) {
      return overlaps.every((o) => c.reviewedOverlaps.contains(o.key))
          ? 'Solapamiento revisado'
          : 'Revisar solapamiento';
    }
    return 'Listo';
  }

  String get _phase => switch (c.phase) {
    ImportPhase.idle => 'Importación',
    ImportPhase.reading => 'Leyendo',
    ImportPhase.review => 'Revisión',
    ImportPhase.confirming => 'Confirmando',
    ImportPhase.imported => 'Importado',
    ImportPhase.alreadyImported => 'Ya importado',
    ImportPhase.error => 'Error',
  };
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final review = c.review;
      final rows = c.session?.interpretation.rows ?? <InterpretedImportRow>[];
      final accountRefs = rows
          .whereType<InterpretedMovement>()
          .map((r) => r.account)
          .toSet();
      final categoryRefs = rows
          .map(
            (r) => switch (r) {
              InterpretedMovement() => r.category,
              InterpretedBudget() => r.category,
            },
          )
          .whereType<ImportCategoryReference>()
          .toSet();
      final batch = switch (c.result) {
        ImportConfirmed(:final batch) => batch,
        ImportAlreadyImported(:final batch) => batch,
        _ => null,
      };
      final periods =
          rows
              .map(
                (r) => switch (r) {
                  InterpretedMovement() => r.valueDate.value.substring(0, 7),
                  InterpretedBudget() => r.month.value.substring(0, 7),
                },
              )
              .toSet()
              .toList()
            ..sort();
      return PopScope(
        canPop: !c.hasSession && c.phase != ImportPhase.confirming,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leave();
        },
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: const Text('Revisión de importación'),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 12,
                    children: [
                      TextButton(
                        onPressed: c.phase == ImportPhase.confirming
                            ? null
                            : _leave,
                        child: Text(widget.returnLabel),
                      ),
                      TextButton(
                        onPressed: c.busy ? null : widget.onHistory,
                        child: const Text('Historial de lotes'),
                      ),
                    ],
                  ),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _phase,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (c.busy) ...[
                    const LinearProgressIndicator(),
                    Text(
                      c.phase == ImportPhase.confirming
                          ? 'Esperando el resultado de SQLite. No se puede cancelar la confirmación.'
                          : 'Leyendo y validando el lote completo…',
                    ),
                  ],
                  if (c.message != null)
                    Semantics(liveRegion: true, child: Text(c.message!)),
                  if (c.session != null) ...[
                    Text(c.session!.file.originalName),
                    Text(
                      'Origen: ${importSourceLabel(c.session!.file.source)}',
                    ),
                  ],
                  if (batch != null) ...[
                    Text(
                      c.result is ImportConfirmed
                          ? 'Lote guardado en la base local: ${batch.movementCount} reales y ${batch.budgetCount} presupuestos.'
                          : 'Estos bytes ya se importaron. Cero altas; los registros corregidos o borrados se conservan.',
                    ),
                    TextButton(
                      onPressed: () => widget.onBatch(batch.id),
                      child: const Text('Consultar lote y origen'),
                    ),
                    for (final period in periods)
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final destination in [
                            'Estado',
                            'Presupuesto',
                            'Real',
                          ])
                            TextButton(
                              onPressed: () =>
                                  widget.onPeriod(destination, period),
                              child: Text('$destination · $period'),
                            ),
                        ],
                      ),
                  ] else ...[
                    for (final issue in [...?review?.issues, ...c.failures])
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          '${issue.sourceOrdinal == null ? 'Lote' : 'Fila ${issue.sourceOrdinal}'}${issue.field == null ? '' : ' · ${issue.field}'}: ${issue.reason}',
                        ),
                      ),
                    if (review != null) ...[
                      Text(
                        'REAL: ${review.movementCount} · original ${importMoney(review.totalCents(budgets: false, original: true))} · interno ${importMoney(review.totalCents(budgets: false, original: false))}',
                      ),
                      Text(
                        'PRESUPUESTO: ${review.budgetCount} · original ${importMoney(review.totalCents(budgets: true, original: true))} · interno ${importMoney(review.totalCents(budgets: true, original: false))}',
                      ),
                      for (final pending in review.pendingReferences)
                        Text(
                          'Pendiente · filas ${pending.sourceOrdinals.join(', ')}: ${pending.reason}',
                        ),
                      for (final ref in accountRefs)
                        OutlinedButton(
                          onPressed: c.busy
                              ? null
                              : () => _resolve(PendingImportAccount(ref)),
                          child: Text(
                            'Resolver cuenta: ${ref.name ?? 'selección global'}',
                          ),
                        ),
                      for (final ref in categoryRefs)
                        OutlinedButton(
                          onPressed: c.busy
                              ? null
                              : () => _resolve(PendingImportCategory(ref)),
                          child: Text(
                            'Resolver categoría: ${ref.path.join(' / ')}',
                          ),
                        ),
                      for (final overlap in review.overlaps)
                        Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Posible duplicado · fila ${overlap.sourceOrdinal}. Se conservarán ambos registros.',
                              ),
                              for (final existing
                                  in c.snapshot!.movements.where(
                                    (m) => m.id == overlap.existingMovementId,
                                  ))
                                Text(
                                  'Registro actual ${existing.id}: ${existing.data.valueDate.value} · ${existing.data.concept} · ${importMoney(existing.data.amountCents)} · cuenta ${existing.data.accountId}',
                                ),
                              CheckboxListTile(
                                title: Text(
                                  'He comparado la fila ${overlap.sourceOrdinal} con ${overlap.existingMovementId}',
                                ),
                                value: c.reviewedOverlaps.contains(overlap.key),
                                onChanged: c.busy
                                    ? null
                                    : (v) => c.markOverlap(
                                        overlap.key,
                                        v ?? false,
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ImportRowsView(
                        rows: rows.skip(_page * 50).take(50).toList(),
                        accountLabel: _account,
                        categoryLabel: _category,
                        statusLabel: _rowStatus,
                        onOriginal: c.busy
                            ? null
                            : (r) => showImportOriginal(context, r),
                      ),
                      if (rows.length > 50)
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: c.busy || _page == 0
                                  ? null
                                  : () => setState(() => _page--),
                              child: const Text('Página anterior'),
                            ),
                            Text(
                              'Página ${_page + 1} de ${(rows.length / 50).ceil()}',
                            ),
                            TextButton(
                              onPressed:
                                  c.busy || (_page + 1) * 50 >= rows.length
                                  ? null
                                  : () => setState(() => _page++),
                              child: const Text('Página siguiente'),
                            ),
                          ],
                        ),
                    ],
                    Wrap(
                      spacing: 12,
                      children: [
                        FilledButton(
                          onPressed: c.canConfirm ? _confirm : null,
                          child: const Text('Confirmar lote completo'),
                        ),
                        OutlinedButton(
                          onPressed: c.busy
                              ? null
                              : c.session == null
                              ? c.retryRead
                              : c.refresh,
                          child: const Text('Revalidar / reintentar'),
                        ),
                      ],
                    ),
                    const Text(
                      'Solo se confirma el lote válido completo. Revisar y cancelar no guarda datos.',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
