import 'package:flutter/services.dart';

import '../domain/export_save.dart';

final class NativeExportSaver implements ExportSaver {
  NativeExportSaver({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('autofinance/export_save');

  final MethodChannel _channel;
  bool _pending = false;

  @override
  Future<ExportSaveResult> save(ExportSaveRequest request) async {
    if (_pending) return const ExportSaveFailed(ExportSaveFailureCode.busy);
    _pending = true;
    try {
      final value = await _channel.invokeMethod<Object?>('save', {
        'sourcePath': request.zipPath,
        'suggestedName': request.suggestedName,
        'mimeType': request.mimeType,
      });
      if (value == null) return const ExportSaveCancelled();
      if (value is Map && value['status'] == 'saved') {
        final location = value['location'];
        if (location == null || (location is String && location.isNotEmpty)) {
          return ExportSaved(location: location as String?);
        }
      }
      return const ExportSaveFailed(ExportSaveFailureCode.writeFailed);
    } on PlatformException catch (error) {
      return ExportSaveFailed(
        ExportSaveFailureCode.values.firstWhere(
          (code) => code.name == error.code,
          orElse: () => ExportSaveFailureCode.writeFailed,
        ),
        incompleteMayRemain:
            error.details is Map &&
            (error.details as Map)['incompleteMayRemain'] == true,
      );
    } on MissingPluginException {
      return const ExportSaveFailed(ExportSaveFailureCode.unavailable);
    } finally {
      _pending = false;
    }
  }
}
