import 'package:flutter/services.dart';

import '../domain/local_csv_selection.dart';

/// Los hosts leen binario en segundo plano; no hay caché ni ruta en Dart.
final class NativeLocalCsvSelector implements LocalCsvSelector {
  NativeLocalCsvSelector({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('autofinance/local_csv');

  final MethodChannel _channel;
  bool _pending = false;

  @override
  Future<LocalCsvSelection> select() async {
    if (_pending) return const LocalCsvFailed(LocalCsvFailureCode.busy);
    _pending = true;
    try {
      final value = await _channel.invokeMethod<Object?>('select');
      if (value == null) return const LocalCsvCancelled();
      if (value is! Map) {
        return const LocalCsvFailed(LocalCsvFailureCode.readFailed);
      }
      final name = value['name'];
      final bytes = value['bytes'];
      if (name is! String ||
          name.trim().isEmpty ||
          name.contains('/') ||
          name.contains('\\') ||
          name.contains('\u0000') ||
          bytes is! Uint8List) {
        return const LocalCsvFailed(LocalCsvFailureCode.readFailed);
      }
      return LocalCsvSelected(name: name, bytes: bytes);
    } on PlatformException catch (error) {
      return LocalCsvFailed(switch (error.code) {
        'accessDenied' => LocalCsvFailureCode.accessDenied,
        'unavailable' => LocalCsvFailureCode.unavailable,
        'busy' => LocalCsvFailureCode.busy,
        _ => LocalCsvFailureCode.readFailed,
      });
    } on MissingPluginException {
      return const LocalCsvFailed(LocalCsvFailureCode.unavailable);
    } finally {
      _pending = false;
    }
  }
}
