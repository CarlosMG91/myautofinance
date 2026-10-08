import 'package:flutter/services.dart';

import '../domain/local_csv_selection.dart';
import 'native_local_file_selector.dart';

/// Fachada compatible; la lectura nativa es compartida con los extractos.
final class NativeLocalCsvSelector implements LocalCsvSelector {
  NativeLocalCsvSelector({MethodChannel? channel})
    : _selector = NativeLocalFileSelector(channel: channel);

  final NativeLocalFileSelector _selector;

  @override
  Future<LocalCsvSelection> select() => _selector.select();
}
