import 'dart:async';

import 'package:myautofinance/core/persistence/unit_of_work.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';
import 'package:myautofinance/features/synchronization/export_saving.dart';
import 'package:myautofinance/features/synchronization/presentation/export_controller.dart';

class ExportFixture
    implements DataExporter, PortableBackupExporter, ExportSaver {
  final filters = <DataExportFilter?>[];
  final prepared = <TestPreparedExport>[];
  final requests = <ExportSaveRequest>[];
  Completer<void>? preparation;
  Completer<ExportSaveResult>? saving;
  ExportSaveResult outcome = const ExportSaved();
  Object? prepareError, saveError;
  bool cleanupFails = false;

  ExportController controller() =>
      ExportController(data: this, complete: this, saver: this);

  @override
  Future<PreparedDataExport> prepare({
    DataExportFilter? filter,
    required DataExportCancellation cancellation,
    void Function(String, int)? onProgress,
  }) async {
    filters.add(filter);
    await preparation?.future;
    cancellation.check();
    if (prepareError != null) throw prepareError!;
    final result = TestPreparedExport(
      prepared.length + 1,
      cleanupFails: cleanupFails,
    );
    prepared.add(result);
    return result;
  }

  @override
  Future<ExportSaveResult> save(ExportSaveRequest request) async {
    requests.add(request);
    if (saveError != null) throw saveError!;
    return saving == null ? outcome : await saving!.future;
  }
}

class TestPreparedExport implements PreparedDataExport {
  TestPreparedExport(this.number, {this.cleanupFails = false});
  final int number;
  final bool cleanupFails;
  int disposals = 0;
  @override
  String get zipPath => '/synthetic/temporary-$number.zip';
  @override
  DatasetState get state =>
      DatasetState(datasetId: 'synthetic', revision: number);
  @override
  DateTime get createdAtUtc => DateTime.utc(2026, 10, 17, 8, number);
  @override
  String get exportId => 'synthetic-$number';
  @override
  Future<void> dispose() async {
    disposals++;
    if (cleanupFails) throw StateError('private-path');
  }
}
