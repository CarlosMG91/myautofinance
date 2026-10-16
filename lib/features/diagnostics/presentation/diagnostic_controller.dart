import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../wealth/wealth.dart' show Month;
import '../diagnostics.dart';

/// Estado de una visita, sin persistencia ni ejecución desde notificaciones.
class DiagnosticController extends ChangeNotifier {
  DiagnosticController(this.executor, {Stream<int>? changes}) {
    _changes = changes?.listen((_) {
      final saved = report;
      if (saved != null) unawaited(validate(saved.selectedMonth));
    });
  }
  final DiagnosticExecutor executor;
  StreamSubscription<int>? _changes;
  DiagnosticCancellation? _cancellation;
  DiagnosticExecution? execution;
  DiagnosticSeverity? severity;
  bool busy = false, obsolete = false, checking = false;
  bool _disposed = false;
  int _request = 0, _validation = 0;
  DiagnosticReport? get report => switch (execution) {
    DiagnosticCompleted(:final report) => report,
    _ => null,
  };

  void filter(DiagnosticSeverity? value) {
    severity = value;
    notifyListeners();
  }

  void invalidate({bool notify = true}) {
    _validation++;
    if (busy) _cancellation?.cancel();
    if (report != null) obsolete = true;
    checking = false;
    if (!_disposed && notify) notifyListeners();
  }

  Future<void> validate(Month month) async {
    final saved = report;
    if (saved == null || obsolete || _disposed) return;
    final request = ++_validation;
    checking = true;
    notifyListeners();
    final current = await executor.isCurrent(saved, month);
    if (_disposed || request != _validation || !identical(saved, report)) {
      return;
    }
    checking = false;
    obsolete = !current;
    notifyListeners();
  }

  Future<void> run(Month month) async {
    if (_disposed || busy) return;
    final request = ++_request;
    _validation++;
    busy = true;
    checking = false;
    execution = null;
    obsolete = false;
    final token = _cancellation = DiagnosticCancellation();
    notifyListeners();
    final result = await executor.execute(month, cancellation: token);
    if (_disposed || request != _request) return;
    execution = result;
    busy = false;
    if (result is DiagnosticCompleted) {
      checking = true;
      notifyListeners();
      await validate(month);
    } else {
      notifyListeners();
    }
  }

  void cancel() => _cancellation?.cancel();

  @override
  void dispose() {
    _disposed = true;
    _cancellation?.cancel();
    _changes?.cancel();
    super.dispose();
  }
}
