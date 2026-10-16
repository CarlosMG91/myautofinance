import '../../wealth/wealth.dart' show Month;
import 'diagnostic_action.dart';
import 'diagnostic_result.dart';
import 'diagnostic_rule.dart';

final class DiagnosticCancellation {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Todas las lecturas del callback deben compartir la misma instantánea.
abstract interface class DiagnosticReadSource {
  Future<T> read<T>(Future<T> Function(DiagnosticReadSession) operation);
  Future<DiagnosticRevision> currentRevision();
}

abstract interface class DiagnosticReadSession {
  DiagnosticRevision get revision;
  Future<DiagnosticRevision> readRevision();
  Future<DiagnosticRuleResult> check(DiagnosticRule rule, Month month);
}

enum DiagnosticSessionFailure { cancelled, readFailure, changedDuringRead }

sealed class DiagnosticExecution {
  const DiagnosticExecution();
}

final class DiagnosticCompleted extends DiagnosticExecution {
  const DiagnosticCompleted(this.report);
  final DiagnosticReport report;
}

/// Sin marcador fiable no se fabrica un informe financiero ni un «todo bien».
final class DiagnosticFailed extends DiagnosticExecution {
  DiagnosticFailed(this.reason)
    : results = List.unmodifiable([
        for (final rule in DiagnosticRule.values)
          DiagnosticRuleResult.notRun(
            rule,
            reason == DiagnosticSessionFailure.cancelled
                ? DiagnosticNotRunReason.cancelled
                : DiagnosticNotRunReason.readFailure,
          ),
      ]);
  final DiagnosticSessionFailure reason;
  final List<DiagnosticRuleResult> results;
  DiagnosticAction? get action => reason == DiagnosticSessionFailure.readFailure
      ? const OpenLocalRecovery()
      : null;
}

/// Solo se ejecuta por llamada explícita. No persiste, repara ni repite.
final class DiagnosticExecutor {
  DiagnosticExecutor(this.source, {DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final DiagnosticReadSource source;
  final DateTime Function() _now;

  Future<DiagnosticExecution> execute(
    Month month, {
    DiagnosticCancellation? cancellation,
  }) async {
    void cancelled() {
      if (cancellation?.isCancelled ?? false) {
        throw DiagnosticSessionFailure.cancelled;
      }
    }

    try {
      cancelled();
      final before = await source.currentRevision();
      final report = await source.read((session) async {
        if (!before.matches(session.revision)) {
          throw DiagnosticSessionFailure.changedDuringRead;
        }
        final results = <DiagnosticRuleResult>[];
        for (final rule in DiagnosticRule.values) {
          cancelled();
          results.add(await session.check(rule, month));
          cancelled();
          if (!before.matches(await session.readRevision())) {
            throw DiagnosticSessionFailure.changedDuringRead;
          }
        }
        return DiagnosticReport(
          executedAt: _now(),
          selectedMonth: month,
          revision: session.revision,
          results: results,
        );
      });
      cancelled();
      if (!report.revision.matches(await source.currentRevision())) {
        return DiagnosticFailed(DiagnosticSessionFailure.changedDuringRead);
      }
      cancelled();
      return DiagnosticCompleted(report);
    } on DiagnosticSessionFailure catch (reason) {
      return DiagnosticFailed(reason);
    } catch (_) {
      return DiagnosticFailed(DiagnosticSessionFailure.readFailure);
    }
  }

  /// La UI consulta vigencia al volver/tras cambios; no vuelve a ejecutar.
  Future<bool> isCurrent(DiagnosticReport report, Month month) async {
    try {
      return !report.isObsolete(await source.currentRevision(), month);
    } catch (_) {
      return false;
    }
  }
}
