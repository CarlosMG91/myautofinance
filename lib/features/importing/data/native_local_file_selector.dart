import 'package:flutter/services.dart';

import '../domain/local_file_selection.dart';

/// Los hosts leen binario en segundo plano; no hay caché ni ruta en Dart.
enum LocalFileHint { csv, xls }

final class NativeLocalFileSelector implements LocalFileSelector {
  NativeLocalFileSelector({
    MethodChannel? channel,
    this.hint = LocalFileHint.csv,
  }) : _channel = channel ?? const MethodChannel('autofinance/local_csv');

  final LocalFileHint hint;
  final MethodChannel _channel;
  bool _pending = false;

  @override
  Future<LocalFileSelection> select() async {
    if (_pending) return const LocalFileFailed(LocalFileFailureCode.busy);
    _pending = true;
    try {
      final value = await _channel.invokeMethod<Object?>(
        'select',
        hint == LocalFileHint.xls ? {'extension': 'xls'} : null,
      );
      if (value == null) return const LocalFileCancelled();
      if (value is! Map) {
        return const LocalFileFailed(LocalFileFailureCode.readFailed);
      }
      final name = value['name'];
      final bytes = value['bytes'];
      if (name is! String ||
          name.trim().isEmpty ||
          name.contains('/') ||
          name.contains('\\') ||
          name.contains('\u0000') ||
          bytes is! Uint8List) {
        return const LocalFileFailed(LocalFileFailureCode.readFailed);
      }
      return LocalFileSelected(name: name, bytes: bytes);
    } on PlatformException catch (error) {
      return LocalFileFailed(switch (error.code) {
        'accessDenied' => LocalFileFailureCode.accessDenied,
        'unavailable' => LocalFileFailureCode.unavailable,
        'busy' => LocalFileFailureCode.busy,
        _ => LocalFileFailureCode.readFailed,
      });
    } on MissingPluginException {
      return const LocalFileFailed(LocalFileFailureCode.unavailable);
    } finally {
      _pending = false;
    }
  }
}
