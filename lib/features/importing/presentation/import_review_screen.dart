import 'package:flutter/material.dart';

import 'dart:async';

import 'package:flutter/services.dart';

import 'dart:ui' show AppExitResponse;

import '../importing.dart';
import 'import_controller.dart';
import 'import_reference_dialog.dart';
import 'import_widgets.dart';
import 'import_layout.dart';
import '../../../ui/autofinance_ui.dart';

class ImportReviewScreen extends StatefulWidget {
  const ImportReviewScreen({
    super.key,
    required this.controller,
    required this.onReturn,
    required this.onHistory,
    required this.onBatch,
    this.onPending,
    this.pendingCount,
    required this.onPeriod,
    this.returnLabel = 'Volver al origen',
  });
  final ImportController controller;
  final VoidCallback onReturn, onHistory;
  final FutureOr<void> Function(String) onBatch;
  final void Function(String, String) onPeriod;
  final String returnLabel;
  final Future<void> Function(String)? onPending;
  final Future<int> Function(String)? pendingCount;
  @override
  State<ImportReviewScreen> createState() => _ImportReviewScreenState();
}

class _ImportReviewScreenState extends State<ImportReviewScreen>
    with WidgetsBindingObserver {
  int _page = 0;
  bool _details = false;
  bool _dialog = false;
  ImportSession? _displayedSession;
  final _headingFocus = FocusNode();
  final _batchFocus = FocusNode();
  int _pendingRevision = 0;
  ImportPhase? _lastPhase;
  String? _lastSelectionMessage;
  ImportController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _headingFocus.dispose();
    _batchFocus.dispose();
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async =>
      await _allowLeave() ? AppExitResponse.exit : AppExitResponse.cancel;
  Future<bool> _allowLeave() async {
    if (c.phase == ImportPhase.confirming || _dialog) return false;
    if (c.selecting) {
      c.cancelSelection();
      return false;
    }
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

  Future<bool> _approveReplacement() async {
    if (_dialog || !mounted) return false;
    _dialog = true;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Descartar la revisión?'),
        content: Text(
          'El nuevo ${c.selectionKind} iniciará otra revisión. Se perderán las asignaciones y los solapamientos revisados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Conservar revisión'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Descartar y cargar'),
          ),
        ],
      ),
    );
    _dialog = false;
    return mounted && approved == true;
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
    ImportPhase.error => 'Error de importación',
  };
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      if (_lastPhase != c.phase ||
          _lastSelectionMessage != c.selectionMessage) {
        _lastPhase = c.phase;
        _lastSelectionMessage = c.selectionMessage;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_dialog) _headingFocus.requestFocus();
        });
      }
      if (_displayedSession != c.session) {
        _displayedSession = c.session;
        _page = 0;
        _details = false;
      }
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
      final issues = [...?review?.issues, ...c.failures];
      final invalidFile = c.session?.interpretation.issues.isNotEmpty ?? false;
      final unreviewed =
          review?.overlaps
              .where((o) => !c.reviewedOverlaps.contains(o.key))
              .length ??
          0;
      final step = batch != null
          ? 4
          : c.phase == ImportPhase.confirming
          ? 3
          : review == null
          ? 0
          : review.pendingReferences.isNotEmpty
          ? 2
          : c.canConfirm
          ? 3
          : 1;
      final blockedReason = c.busy
          ? 'Espera a que termine la selección, lectura o confirmación del lote.'
          : issues.isNotEmpty
          ? 'Corrige todos los errores antes de confirmar. No se importará ninguna fila.'
          : review?.pendingReferences.isNotEmpty == true
          ? 'Resuelve las cuentas y categorías pendientes antes de confirmar.'
          : unreviewed > 0
          ? 'Compara y marca todos los posibles duplicados antes de confirmar.'
          : 'Selecciona y revisa un archivo completo antes de confirmar.';
      return PopScope(
        canPop:
            !c.selecting && !c.hasSession && c.phase != ImportPhase.confirming,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leave();
        },
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): _leave},
          child: Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                child: AfPageLayout(
                  page: AfPageSlots(
                    title: 'Revisión de importación',
                    contextTrail: const Text(
                      'Gestión / Importaciones · la revisión no escribe datos',
                    ),
                    actions: [
                      TextButton(
                        onPressed: c.phase == ImportPhase.confirming
                            ? null
                            : _leave,
                        child: Text(widget.returnLabel),
                      ),
                      AfAction(
                        label: 'Historial de lotes',
                        variant: AfActionVariant.link,
                        onPressed: c.busy ? null : widget.onHistory,
                      ),
                    ],
                    body: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 24,
                      children: [
                        ImportSteps(current: step),
                        Semantics(
                          liveRegion: true,
                          header: true,
                          child: Focus(
                            focusNode: _headingFocus,
                            child: Text(
                              _phase,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                        ),
                        if (c.busy) ...[
                          const LinearProgressIndicator(
                            semanticsLabel: 'Procesando importación',
                          ),
                          Text(
                            c.phase == ImportPhase.confirming
                                ? 'Esperando el resultado de SQLite. No se puede cancelar la confirmación.'
                                : 'Leyendo y validando el lote completo…',
                          ),
                        ],
                        if (c.message != null)
                          AfStatus(
                            kind: AfStatusKind.error,
                            message: c.message!,
                          ),
                        // Ningún diagnóstico bloqueante se oculta en el detalle.
                        if (batch == null && issues.isNotEmpty)
                          ImportSection(
                            title: 'El lote contiene errores. No se puede confirmar.',
                            children: [
                              const Text(
                                'Cero cambios. Corrige el archivo o las asignaciones y vuelve a revisar.',
                              ),
                              for (final issue in issues)
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    '${issue.sourceOrdinal == null
                                        ? 'Lote'
                                        : issue.sourceOrdinal == 1
                                        ? 'Cabecera · registro 1'
                                        : 'Fila ${issue.sourceOrdinal}'}'
                                    '${issue.field == null ? '' : ' · ${issue.field}'}: ${issue.reason}',
                                    style: const TextStyle(
                                      color: AfTokens.error,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        if (c.supportsFileSelection)
                          ImportSection(
                            title: c.session == null
                                ? 'Selecciona tu archivo'
                                : 'Archivo seleccionado',
                            children: [
                              if (c.session != null) ...[
                                Text(c.session!.file.originalName),
                                Text(
                                  'Origen: ${importSourceLabel(c.session!.file.source)}',
                                ),
                              ],
                              if (c.session == null)
                                Text(
                                  c.supportsBank
                                      ? 'Extracto original de Openbank (.xls). Un archivo por carga. Elige y confirma la cuenta de destino antes de importar.'
                                      : 'CSV histórico · UTF-8 · separador ; · cabeceras exactas. Un archivo por carga.',
                                ),
                              if (c.session == null)
                                Text(
                                  c.supportsBank
                                      ? 'Solo movimientos reales, pendientes de categorizar. Los saldos del extracto no modifican las fotos patrimoniales.'
                                      : 'El presupuesto CSV tiene signo contrario al interno. La normalización la realiza el importador una sola vez.',
                                ),
                              AfAction(
                                label: c.session == null
                                    ? 'Seleccionar ${c.selectionKind}'
                                    : 'Volver a cargar ${c.selectionKind}',
                                icon: AfIcons.importFile,
                                variant: c.session == null
                                    ? AfActionVariant.primary
                                    : AfActionVariant.secondary,
                                onPressed: c.busy || _dialog
                                    ? null
                                    : () => c.selectFile(
                                        approveReplacement: _approveReplacement,
                                      ),
                              ),
                              if (c.selecting)
                                const Text(
                                  'Seleccionando y leyendo el archivo…',
                                ),
                              if (c.selectionMessage != null)
                                Semantics(
                                  liveRegion: true,
                                  child: Text(c.selectionMessage!),
                                ),
                              if (c.session == null)
                                const Text(
                                  'Los errores se corrigen en el archivo original y se vuelve a cargar. No se editan filas aquí.',
                                ),
                            ],
                          )
                        else if (c.session != null)
                          ImportSection(
                            title: 'Archivo seleccionado',
                            children: [
                              Text(c.session!.file.originalName),
                              Text(
                                'Origen: ${importSourceLabel(c.session!.file.source)}',
                              ),
                            ],
                          ),
                        if (batch != null)
                          ImportSection(
                            title: c.result is ImportConfirmed
                                ? 'Importación completada'
                                : 'Mismo contenido ya confirmado',
                            tone: AfCardTone.real,
                            children: [
                              Text(
                                c.result is ImportConfirmed
                                    ? 'Lote guardado en la base local: ${batch.movementCount} reales y ${batch.budgetCount} presupuestos.'
                                    : 'Estos bytes ya se importaron. Cero altas; los registros corregidos o borrados se conservan.',
                              ),
                              const Text(
                                'Las fotos patrimoniales se conservan. El resultado corresponde al lote completo.',
                              ),
                              if (widget.onPending != null &&
                                  widget.pendingCount != null)
                                ImportPendingLink(
                                  key: ValueKey((batch.id, _pendingRevision)),
                                  batchId: batch.id,
                                  open: widget.onPending!,
                                  count: widget.pendingCount!,
                                ),
                              TextButton(
                                focusNode: _batchFocus,
                                onPressed: () async {
                                  await widget.onBatch(batch.id);
                                  if (!mounted) return;
                                  setState(() {
                                    _pendingRevision++;
                                  });
                                  _batchFocus.requestFocus();
                                },
                                child: const Text('Consultar lote y origen'),
                              ),
                              for (final period in periods)
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final destination in [
                                      'Estado',
                                      'Presupuesto',
                                      'Real',
                                    ])
                                      AfAction(
                                        label: '$destination · $period',
                                        variant: AfActionVariant.link,
                                        onPressed: () => widget.onPeriod(
                                          destination,
                                          period,
                                        ),
                                      ),
                                  ],
                                ),
                            ],
                          )
                        else ...[
                          if (review != null) ...[
                            AfResponsiveGrid(
                              columns: 2,
                              children: [
                                for (final budgets in [false, true])
                                  ImportSection(
                                    title: budgets ? 'PRESUPUESTO' : 'REAL',
                                    tone: budgets
                                        ? AfCardTone.budget
                                        : AfCardTone.real,
                                    children: [
                                      if (invalidFile)
                                        Text(
                                          '${budgets ? 'PRESUPUESTO' : 'REAL'}: conteo y totales CSV/interno no disponibles.',
                                        )
                                      else ...[
                                        Text(
                                          'Registros del archivo: ${budgets ? review.budgetCount : review.movementCount}',
                                        ),
                                        AfValueRow(
                                          label: 'Total original',
                                          value: AfNumericText(
                                            importMoney(
                                              review.totalCents(
                                                budgets: budgets,
                                                original: true,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const Text(
                                          'Total normalizado · importe interno',
                                        ),
                                        Text(
                                          importMoney(
                                            review.totalCents(
                                              budgets: budgets,
                                              original: false,
                                            ),
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineMedium
                                              ?.copyWith(
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        Text(
                                          budgets
                                              ? 'Sin cuenta. Categorías obligatorias resueltas antes de confirmar.'
                                              : 'Cuenta obligatoria. Los reales sin categoría quedan pendientes de categorizar.',
                                        ),
                                      ],
                                    ],
                                  ),
                              ],
                            ),
                            if (invalidFile)
                              const Text(
                                'El archivo contiene errores. Cero cambios en la base local.',
                              ),
                            if (accountRefs.isNotEmpty ||
                                categoryRefs.isNotEmpty)
                              ImportSection(
                                title: 'Asignación de referencias',
                                children: [
                                  const Text(
                                    'Cada decisión se aplica a todas las filas de la misma referencia. Las altas preparadas solo se guardan al confirmar.',
                                  ),
                                  for (final pending
                                      in review.pendingReferences)
                                    Text(
                                      'Pendiente · filas ${pending.sourceOrdinals.join(', ')}: ${pending.reason}',
                                    ),
                                  for (final ref in accountRefs) ...[
                                    Text(
                                      'Cuenta original: ${ref.name ?? 'selección global'} · destino: ${_account(rows.whereType<InterpretedMovement>().firstWhere((r) => r.account == ref))}',
                                    ),
                                    AfAction(
                                      label:
                                          'Resolver cuenta: ${ref.name ?? 'selección global'}',
                                      onPressed: c.busy
                                          ? null
                                          : () => _resolve(
                                              PendingImportAccount(ref),
                                            ),
                                    ),
                                  ],
                                  for (final ref in categoryRefs) ...[
                                    Text(
                                      'Categoría original: ${ref.path.join(' / ')} · destino: ${_category(ref)}',
                                    ),
                                    AfAction(
                                      label:
                                          'Resolver categoría: ${ref.path.join(' / ')}',
                                      onPressed: c.busy
                                          ? null
                                          : () => _resolve(
                                              PendingImportCategory(ref),
                                            ),
                                    ),
                                  ],
                                ],
                              ),
                            if (review.overlaps.isNotEmpty)
                              ImportSection(
                                title: 'Revisa los posibles duplicados',
                                children: [
                                  const Text(
                                    'No se eliminan filas por parecido. Los movimientos idénticos del mismo archivo se conservan.',
                                  ),
                                  for (final overlap in review.overlaps) ...[
                                    Text(
                                      'Posible duplicado · fila ${overlap.sourceOrdinal}. Se conservarán ambos registros.',
                                    ),
                                    for (final incoming in rows.where(
                                      (r) =>
                                          r.sourceOrdinal ==
                                          overlap.sourceOrdinal,
                                    ))
                                      Text(
                                        'Fila nueva: ${incoming.concept} · ${importMoney(incoming.amount.internalCents)}',
                                      ),
                                    for (final existing
                                        in c.snapshot!.movements.where(
                                          (m) =>
                                              m.id ==
                                              overlap.existingMovementId,
                                        ))
                                      Text(
                                        'Registro actual ${existing.id}: ${existing.data.valueDate.value} · ${existing.data.concept} · ${importMoney(existing.data.amountCents)} · cuenta ${existing.data.accountId}',
                                      ),
                                    CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        'He comparado la fila ${overlap.sourceOrdinal} con ${overlap.existingMovementId}',
                                      ),
                                      value: c.reviewedOverlaps.contains(
                                        overlap.key,
                                      ),
                                      onChanged: c.busy
                                          ? null
                                          : (v) => c.markOverlap(
                                              overlap.key,
                                              v ?? false,
                                            ),
                                    ),
                                  ],
                                ],
                              ),
                            AfCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                spacing: 12,
                                children: [
                                  TextButton(
                                    onPressed: () =>
                                        setState(() => _details = !_details),
                                    child: Text(
                                      _details
                                          ? 'Ocultar detalle de filas'
                                          : 'Ver detalle de filas',
                                    ),
                                  ),
                                  Text(
                                    '${rows.length} filas interpretadas · originales, importes normalizados, cuentas y categorías.',
                                  ),
                                  if (_details) ...[
                                    Text(
                                      c.supportsBank
                                          ? 'Fila indica la fila física de la tabla del extracto. Los originales conservan su localización.'
                                          : 'Fila indica el ordinal del registro CSV. En textos multilínea puede diferir de la línea física.',
                                    ),
                                    ImportRowsView(
                                      originalLabel: c.supportsCsv
                                          ? 'Importe CSV'
                                          : 'Original',
                                      rows: rows
                                          .skip(_page * 50)
                                          .take(50)
                                          .toList(),
                                      accountLabel: _account,
                                      categoryLabel: _category,
                                      statusLabel: _rowStatus,
                                      onOriginal: c.busy
                                          ? null
                                          : (r) =>
                                                showImportOriginal(context, r),
                                    ),
                                    if (rows.length > 50)
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          TextButton(
                                            onPressed: c.busy || _page == 0
                                                ? null
                                                : () => setState(() => _page--),
                                            child: const Text(
                                              'Página anterior',
                                            ),
                                          ),
                                          Text(
                                            'Página ${_page + 1} de ${(rows.length / 50).ceil()}',
                                          ),
                                          TextButton(
                                            onPressed:
                                                c.busy ||
                                                    (_page + 1) * 50 >=
                                                        rows.length
                                                ? null
                                                : () => setState(() => _page++),
                                            child: const Text(
                                              'Página siguiente',
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                          ImportSection(
                            title: 'Confirmar el lote completo',
                            children: [
                              if (!c.canConfirm) Text(blockedReason),
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                children: [
                                  FilledButton(
                                    onPressed: c.canConfirm ? _confirm : null,
                                    child: const Text(
                                      'Confirmar lote completo',
                                    ),
                                  ),
                                  AfAction(
                                    label: 'Revalidar / reintentar',
                                    onPressed: c.busy || !c.hasSession
                                        ? null
                                        : c.session == null
                                        ? c.retryRead
                                        : c.refresh,
                                  ),
                                ],
                              ),
                              const Text(
                                'Solo se confirma el lote válido completo. Revisar y cancelar no guarda datos.',
                              ),
                              const Text(
                                'La confirmación vuelve a comprobar referencias, conflictos y huella. Un fallo revierte el lote completo.',
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
          ),
        ),
      );
    },
  );
}
