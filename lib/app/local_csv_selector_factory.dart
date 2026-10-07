import '../features/importing/data/native_local_csv_selector.dart';
import '../features/importing/importing.dart';

/// Composición disponible para el flujo CSV; construir no abre el selector.
LocalCsvSelector createLocalCsvSelector() => NativeLocalCsvSelector();
