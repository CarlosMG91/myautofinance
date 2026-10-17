import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/features/synchronization/data/native_export_saver.dart';
import 'package:myautofinance/features/synchronization/export_saving.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/export_save');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final request = ExportSaveRequest(
    zipPath: 'C:/temporal/prueba.zip',
    suggestedName: 'autofinance-datos-20261016T120000Z.zip',
  );
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('Solo nombre neutro, sin nombres de personas ni rutas de destino', () {
    for (final name in [
      'persona.zip',
      '../autofinance-datos.zip',
      'cuenta.zip',
    ]) {
      expect(
        () => ExportSaveRequest(zipPath: 'temp.zip', suggestedName: name),
        throwsArgumentError,
      );
    }
  });
  test(
    'Envía ruta temporal y MIME; espera confirmación nativa sin bytes',
    () async {
      final completion = Completer<Object?>();
      messenger.setMockMethodCallHandler(channel, (call) {
        expect(call.method, 'save');
        expect(call.arguments, {
          'sourcePath': request.zipPath,
          'suggestedName': request.suggestedName,
          'mimeType': 'application/zip',
        });
        return completion.future;
      });
      final saver = NativeExportSaver(channel: channel);
      var completed = false;
      final result = saver.save(request).then((value) {
        completed = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      expect(
        (await saver.save(request) as ExportSaveFailed).code,
        ExportSaveFailureCode.busy,
      );
      completion.complete({
        'status': 'saved',
        'location': 'content://provider/document/123',
      });
      expect(
        (await result as ExportSaved).location,
        'content://provider/document/123',
      );
    },
  );
  test('Cancelación y ubicación no expuesta', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    final saver = NativeExportSaver(channel: channel);
    expect(await saver.save(request), isA<ExportSaveCancelled>());
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {'status': 'saved'},
    );
    expect((await saver.save(request) as ExportSaved).location, isNull);
  });
  test(
    'Nombre final del proveedor y ruta Windows sin confundir nombre sugerido',
    () async {
      final saver = NativeExportSaver(channel: channel);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'status': 'saved',
          'location': 'content://synthetic/document/7',
          'displayName': 'elegido (1).zip',
        },
      );
      expect(
        (await saver.save(request) as ExportSaved).displayName,
        'elegido (1).zip',
      );
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'status': 'saved',
          'location': r'C:\synthetic\elegido.zip',
        },
      );
      expect(
        (await saver.save(request) as ExportSaved).displayName,
        'elegido.zip',
      );
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'status': 'saved',
          'location': 'content://synthetic/document/7',
        },
      );
      expect((await saver.save(request) as ExportSaved).displayName, isNull);
    },
  );
  for (final code in ExportSaveFailureCode.values) {
    test('Fallo claro ${code.name} y posible incompleto', () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(
          code: code.name,
          details: {'incompleteMayRemain': true},
        );
      });
      final result = await NativeExportSaver(
        channel: channel,
      ).save(request) as ExportSaveFailed;
      expect(result.code, code);
      expect(result.message, isNotEmpty);
      expect(result.incompleteMayRemain, isTrue);
    });
  }
  test('Protocolo incorrecto o plugin ausente no afirman éxito', () async {
    final saver = NativeExportSaver(channel: channel);
    for (final value in [
      true,
      {'status': 'saved', 'location': 42},
      {'status': 'pending'},
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => value);
      expect(
        (await saver.save(request) as ExportSaveFailed).code,
        ExportSaveFailureCode.writeFailed,
      );
    }
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw MissingPluginException(),
    );
    expect(
      (await saver.save(request) as ExportSaveFailed).code,
      ExportSaveFailureCode.unavailable,
    );
  });
}
