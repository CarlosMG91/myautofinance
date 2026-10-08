import '../features/importing/data/native_local_file_selector.dart';
import '../features/importing/importing.dart';

/// Solo orienta el selector: la extensión no acredita el formato bancario.
LocalFileSelector createOpenbankSelector() =>
    NativeLocalFileSelector(hint: LocalFileHint.xls);
