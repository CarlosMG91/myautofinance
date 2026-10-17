import 'package:flutter/foundation.dart';

import '../../../core/persistence/unit_of_work.dart';
import '../domain/data_export.dart';
import '../domain/portable_backup_export.dart';
import '../domain/export_save.dart';

enum ExportMode { data, complete }

enum ExportPhase { idle, preparing, saving }

/// Coordina un único intento. No conserva ZIP para reintentos o filtros nuevos.
class ExportController extends ChangeNotifier {
  ExportController({
    required this.data,
    required this.complete,
    required this.saver,
  });
  final DataExporter data;
  final PortableBackupExporter complete;
  final ExportSaver saver;

  ExportMode mode = ExportMode.data;
  bool months = false;
  String from = '', through = '';
  bool dirty = false;
  ExportPhase phase = ExportPhase.idle;
  ExportSaveResult? result;
  String? message;
  String? cleanupWarning;
  DatasetState? capturedState;
  DateTime? capturedAt;
  String? suggestedName;
  String? exportedScope;
  ExportMode? exportedMode;
  DataExportCancellation? _cancellation;
  bool _disposed = false;

  bool get busy => phase != ExportPhase.idle;
  String get scope => mode == ExportMode.complete || !months
      ? 'Todo el histórico'
      : '$from a $through · meses completos, ambos incluidos';

  void select({ExportMode? mode, bool? months, String? from, String? through}) {
    if (busy) return;
    this.mode = mode ?? this.mode;
    this.months = months ?? this.months;
    this.from = from ?? this.from;
    this.through = through ?? this.through;
    dirty = true;
    result = null;
    message = null;
    capturedState = null;
    capturedAt = null;
    _notify();
  }

  DataExportFilter _filter() {
    if (mode == ExportMode.complete || !months) {
      return const DataExportFilter.all();
    }
    return DataExportFilter.months(from: '$from-01', through: '$through-01');
  }

  void cancelPreparation() {
    if (phase == ExportPhase.preparing) _cancellation?.cancel();
  }

  Future<void> save() async {
    if (busy || _disposed) return;
    final DataExportFilter filter;
    try {
      filter = _filter();
    } on ArgumentError {
      message = 'Elige ambos meses (AAAA-MM). Desde debe ser anterior o igual a Hasta.';
      _notify();
      return;
    }
    result = null;
    message = null;
    cleanupWarning = null;
    capturedState = null;
    capturedAt = null;
    exportedScope = scope;
    exportedMode = mode;
    final cancellation = _cancellation = DataExportCancellation();
    phase = ExportPhase.preparing;
    _notify();
    PreparedDataExport? prepared;
    try {
      prepared = mode == ExportMode.complete
          ? await complete.prepare(cancellation: cancellation)
          : await data.prepare(filter: filter, cancellation: cancellation);
      cancellation.check();
      capturedState = prepared.state;
      capturedAt = prepared.createdAtUtc.toUtc();
      final stamp = capturedAt!
          .toIso8601String()
          .split('.')
          .first
          .replaceAll(RegExp('[-:]'), '');
      suggestedName =
          'autofinance-${mode == ExportMode.complete ? 'copia' : 'datos'}-${stamp}Z.zip';
      phase = ExportPhase.saving;
      _notify();
      // No se cancela ni se elimina el origen mientras el sistema lo está usando.
      result = await saver.save(
        ExportSaveRequest(
          zipPath: prepared.zipPath,
          suggestedName: suggestedName!,
        ),
      );
      message = switch (result!) {
        ExportSaved() =>
          'ZIP guardado. El sistema ha confirmado la escritura y el cierre.',
        ExportSaveCancelled() =>
          'Has cancelado el selector. No se ha guardado ningún archivo.',
        ExportSaveFailed failure =>
          '${failure.message}${failure.incompleteMayRemain ? ' Puede quedar un documento incompleto de esta operación. Revisa el destino y reintenta con otro nombre.' : ''}',
      };
      if (result is ExportSaved) dirty = false;
    } on DataExportFailure catch (failure) {
      message = switch (failure.code) {
        DataExportFailureCode.cancelled =>
          'Operación cancelada. No se ha guardado ningún ZIP.',
        DataExportFailureCode.invalidSnapshot =>
          'No se pudo validar la captura. Reintenta la exportación.',
        DataExportFailureCode.limitExceeded => 'La exportación supera el tamaño permitido. Revisa el ámbito o el espacio disponible.',
        DataExportFailureCode.storage => 'No se pudo preparar el ZIP. Comprueba el espacio disponible y reintenta.',
      };
    } catch (_) {
      // Nunca mostrar excepciones que puedan contener datos financieros o rutas privadas.
      message = phase == ExportPhase.saving
          ? 'No se pudo confirmar el guardado. Revisa el destino antes de reintentar con otro nombre.'
          : 'No se pudo preparar el ZIP. Conservamos tu selección para reintentar.';
    } finally {
      try {
        await prepared?.dispose();
      } catch (_) {
        cleanupWarning = 'No se pudo liberar el temporal privado. El resultado del guardado indicado se conserva.';
      }
      _cancellation = null;
      phase = ExportPhase.idle;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancelPreparation();
    super.dispose();
  }
}
