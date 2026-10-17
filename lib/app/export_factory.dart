import '../features/synchronization/data/native_export_saver.dart';
import '../features/synchronization/presentation/export_controller.dart';
import 'data/sqlite/local_database_store.dart';
import 'data_export_factory.dart';
import 'portable_backup_export_factory.dart';

/// Se crea por visita. Ninguna exportación ocurre al componer los servicios.
ExportController createExportController(LocalDatabaseStore store) =>
    ExportController(
      data: createDataExporter(store: store),
      complete: createPortableBackupExporter(store: store),
      saver: NativeExportSaver(),
    );
