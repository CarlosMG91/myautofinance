import 'package:flutter/foundation.dart';

import '../importing.dart';

/// Se resuelve por operación para no retener una conexión sustituida al restaurar.
typedef ImportServicesLoader = Future<ImportServices> Function();

typedef CsvFilePreparation = Future<ImportFile> Function(LocalCsvSelected);

class ImportServices {
  const ImportServices({
    required this.source,
    required this.previewer,
    required this.confirmer,
    required this.history,
  });
  final ImportPreviewSource source;
  final ImportPreviewer previewer;
  final ImportConfirmer confirmer;
  final ImportHistoryRepository history;
}

enum ImportPhase {
  idle,
  reading,
  review,
  confirming,
  imported,
  alreadyImported,
  error,
}

class ImportController extends ChangeNotifier {
  ImportController(
    this.load, {
    this.csvSelector,
    this.prepareCsv,
    this.csvAdapter,
  });
  final ImportServicesLoader load;
  final LocalCsvSelector? csvSelector;
  final CsvFilePreparation? prepareCsv;
  final ImportAdapter? csvAdapter;
  bool selecting = false;
  String? selectionMessage;
  bool get supportsCsv => csvSelector != null;
  ImportPhase phase = ImportPhase.idle;
  ImportSession? session;
  ImportReview? review;
  ImportPreviewSnapshot? snapshot;
  ImportConfirmationResult? result;
  List<ImportIssue> failures = [];
  String? message;
  final reviewedOverlaps = <String>{};
  ImportFile? _file;
  ImportAdapter? _adapter;
  int _generation = 0;
  int _selectionGeneration = 0;
  bool _disposed = false;

  bool get busy =>
      selecting ||
      phase == ImportPhase.reading ||
      phase == ImportPhase.confirming;
  bool get hasSession => _file != null && result == null;
  bool get canConfirm =>
      !busy &&
      result == null &&
      (review?.canRequestConfirmation ?? false) &&
      reviewedOverlaps.containsAll(review!.overlaps.map((o) => o.key));

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  /// La cancelación del selector conserva la sesión vigente. Solo un reemplazo
  /// aceptado descarta sus asignaciones y marcas, antes de preparar los bytes.
  Future<void> selectCsv({
    required Future<bool> Function() approveReplacement,
  }) async {
    if (_disposed ||
        selecting ||
        phase == ImportPhase.confirming ||
        !supportsCsv) {
      return;
    }
    selecting = true;
    selectionMessage = null;
    final generation = ++_selectionGeneration;
    _emit();
    LocalCsvSelection selected;
    try {
      selected = await csvSelector!.select();
    } catch (_) {
      selected = const LocalCsvFailed(LocalCsvFailureCode.readFailed);
    }
    if (_disposed || generation != _selectionGeneration || !selecting) return;
    switch (selected) {
      case LocalCsvCancelled():
        selectionMessage =
            'Selección cancelada. Se conserva la revisión anterior.';
      case LocalCsvFailed(:final code):
        selectionMessage = switch (code) {
          LocalCsvFailureCode.accessDenied => 'Acceso denegado. Comprueba el permiso del archivo y vuelve a cargar CSV.',
          LocalCsvFailureCode.unavailable => 'Documento no disponible. Comprueba el original y vuelve a cargar CSV.',
          LocalCsvFailureCode.busy =>
            'Ya hay un selector abierto. Ciérralo y vuelve a cargar CSV.',
          LocalCsvFailureCode.readFailed => 'No se pudo leer el archivo. Comprueba el original y vuelve a cargar CSV.',
        };
      case LocalCsvSelected():
        if ((_file != null || session != null) && !await approveReplacement()) {
          if (_disposed || generation != _selectionGeneration) return;
          selecting = false;
          _emit();
          return;
        }
        if (_disposed || generation != _selectionGeneration) return;
        discard();
        final nextGeneration = _generation;
        phase = ImportPhase.reading;
        _emit();
        try {
          final file = await prepareCsv!(selected);
          if (_disposed || nextGeneration != _generation) return;
          phase = ImportPhase.idle;
          await start(file, csvAdapter!);
        } catch (_) {
          if (_disposed || nextGeneration != _generation) return;
          phase = ImportPhase.error;
          message = 'No se pudo preparar el CSV. Corrige el original y vuelve a cargar CSV. Cero cambios.';
          _emit();
        }
        return;
    }
    selecting = false;
    _emit();
  }

  void cancelSelection() {
    if (!selecting) return;
    selecting = false;
    ++_selectionGeneration;
    _emit();
  }

  Future<void> start(ImportFile file, ImportAdapter adapter) async {
    if (busy || hasSession) return;
    _file = file;
    _adapter = adapter;
    await retryRead();
  }

  Future<void> retryRead() async {
    if (busy || _file == null || _adapter == null) return;
    final generation = ++_generation;
    phase = ImportPhase.reading;
    message = null;
    result = null;
    failures = [];
    _emit();
    try {
      if (_adapter!.source != _file!.source) {
        throw StateError('Origen incompatible');
      }
      final interpretation = await _adapter!.interpret(_file!);
      if (_disposed || generation != _generation) return;
      session = ImportSession(file: _file!, interpretation: interpretation);
      await _preview(generation);
    } catch (_) {
      if (_disposed || generation != _generation) return;
      phase = ImportPhase.error;
      message = 'No se pudo leer el lote. Puedes reintentar o cancelar.';
      _emit();
    }
  }

  Future<void> refresh({ImportReferenceBindings? bindings}) async {
    if (busy || session == null || result != null) return;
    final generation = ++_generation;
    phase = ImportPhase.reading;
    failures = [];
    message = null;
    reviewedOverlaps.clear();
    _emit();
    await _preview(generation, bindings: bindings ?? review?.bindings);
  }

  Future<void> _preview(
    int generation, {
    ImportReferenceBindings? bindings,
  }) async {
    final currentSession = session!;
    try {
      final services = await load();
      if (_disposed || generation != _generation) return;
      final data = await services.source.read(currentSession);
      if (_disposed || generation != _generation) return;
      if (supportsCsv && data.sameFileBatchId != null) {
        final batch = await services.history.getBatch(data.sameFileBatchId!);
        if (_disposed || generation != _generation) return;
        if (batch == null) throw StateError('Lote no disponible');
        snapshot = data;
        result = ImportAlreadyImported(batch);
        phase = ImportPhase.alreadyImported;
        _emit();
        return;
      }
      final next = await services.previewer.preview(
        currentSession,
        bindings: bindings,
      );
      if (_disposed || generation != _generation) return;
      snapshot = data;
      review = next;
      phase = next.issues.isEmpty ? ImportPhase.review : ImportPhase.error;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      phase = ImportPhase.error;
      message = 'No se pudo revisar la base local. Conservamos la sesión para reintentar.';
      // Una lectura fallida nunca deja disponible una revisión anterior válida.
      review = ImportReview(
        session: currentSession,
        bindings: bindings,
        issues: [
          ...currentSession.issues,
          const ImportIssue(
            code: ImportIssueCode.persistence,
            reason: 'Revalida el lote antes de confirmar.',
          ),
        ],
      );
    }
    _emit();
  }

  Future<void> bindAccount(
    ImportAccountReference ref, {
    String? id,
    ImportNewAccount? plan,
  }) {
    if (busy || result != null || review == null) return Future.value();
    final b = review!.bindings;
    final accounts = Map<ImportAccountReference, String>.of(b.accounts)
      ..remove(ref);
    final plans = Map<ImportAccountReference, ImportNewAccount>.of(
      b.newAccounts,
    )..remove(ref);
    if (id != null) accounts[ref] = id;
    if (plan != null) plans[ref] = plan;
    return refresh(
      bindings: ImportReferenceBindings(
        accounts: accounts,
        categories: b.categories,
        newAccounts: plans,
        newCategories: b.newCategories,
      ),
    );
  }

  Future<void> bindCategory(
    ImportCategoryReference ref, {
    String? id,
    ImportNewCategory? plan,
  }) {
    if (busy || result != null || review == null) return Future.value();
    final b = review!.bindings;
    final categories = Map<ImportCategoryReference, String>.of(b.categories)
      ..remove(ref);
    final plans = Map<ImportCategoryReference, ImportNewCategory>.of(
      b.newCategories,
    )..remove(ref);
    if (id != null) categories[ref] = id;
    if (plan != null) plans[ref] = plan;
    // Elimina antecesores preparados que han dejado de utilizarse.
    final used = <ImportCategoryReference>{};
    void retain(ImportCategoryReference ref) {
      if (!plans.containsKey(ref) || !used.add(ref)) return;
      final parent = plans[ref]?.parent?.proposedReference;
      if (parent != null) retain(parent);
    }

    for (final row in session!.interpretation.rows) {
      final ref = switch (row) {
        InterpretedMovement() => row.category,
        InterpretedBudget() => row.category,
      };
      if (ref != null) retain(ref);
    }
    plans.removeWhere((ref, _) => !used.contains(ref));
    return refresh(
      bindings: ImportReferenceBindings(
        accounts: b.accounts,
        categories: categories,
        newAccounts: b.newAccounts,
        newCategories: plans,
      ),
    );
  }

  void markOverlap(String key, bool value) {
    if (busy ||
        result != null ||
        review == null ||
        !review!.overlaps.any((o) => o.key == key)) {
      return;
    }
    value ? reviewedOverlaps.add(key) : reviewedOverlaps.remove(key);
    _emit();
  }

  Future<void> confirm() async {
    if (!canConfirm) return;
    final request = ImportConfirmationRequest(
      review: review!,
      reviewedOverlapKeys: reviewedOverlaps,
    );
    phase = ImportPhase.confirming;
    failures = [];
    message = null;
    _emit();
    ImportConfirmationResult response;
    try {
      response = await (await load()).confirmer.confirm(request);
    } catch (_) {
      response = ImportRejected(const [
        ImportIssue(
          code: ImportIssueCode.persistence,
          reason: 'No se pudo confirmar. Reintenta: la huella evita una segunda carga.',
        ),
      ]);
    }
    if (_disposed) return;
    switch (response) {
      case ImportConfirmed():
        result = response;
        phase = ImportPhase.imported;
      case ImportAlreadyImported():
        result = response;
        phase = ImportPhase.alreadyImported;
      case ImportRejected():
        // La nueva revisión muestra referencias/solapamientos que hayan cambiado.
        reviewedOverlaps.clear();
        await _preview(++_generation, bindings: request.review.bindings);
        if (_disposed) return;
        if (result is ImportAlreadyImported) {
          _emit();
          return;
        }
        failures = response.issues;
        phase = ImportPhase.error;
        message = 'La confirmación no se completó. Revisa el lote y vuelve a intentarlo.';
    }
    _emit();
  }

  bool discard() {
    if (phase == ImportPhase.confirming) return false;
    ++_generation;
    ++_selectionGeneration;
    selecting = false;
    selectionMessage = null;
    _file = null;
    _adapter = null;
    session = null;
    review = null;
    snapshot = null;
    result = null;
    failures = [];
    message = null;
    reviewedOverlaps.clear();
    phase = ImportPhase.idle;
    _emit();
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}
