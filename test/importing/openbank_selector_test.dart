import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/openbank_selector_factory.dart';
import 'package:myautofinance/features/importing/data/native_local_file_selector.dart';
import 'package:myautofinance/features/importing/importing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('autofinance/local_csv');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('La composición no abre el selector hasta la petición explícita', () {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return null;
    });
    expect(createOpenbankSelector(), isA<LocalFileSelector>());
    expect(calls, 0);
  });

  test('Conserva bytes, BOM, CRLF, LF y nombre sin exigir extensión', () async {
    final original = Uint8List.fromList([
      0xef,
      0xbb,
      0xbf,
      65,
      59,
      66,
      13,
      10,
      0xc3,
      0xb1,
      10,
      0,
    ]);
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'select');
      expect(call.arguments, {'extension': 'xls'});
      return {'name': 'extracto-sintético.bin', 'bytes': original};
    });
    final result =
        await NativeLocalFileSelector(hint: LocalFileHint.xls).select()
            as LocalFileSelected;
    expect(result.name, 'extracto-sintético.bin');
    expect(result.bytes, original);
    expect(sha256.convert(result.bytes), sha256.convert(original));
    expect(() => result.bytes[0] = 0, throwsUnsupportedError);
    original[0] = 0;
    expect(result.bytes[0], 0xef);
  });

  test('Archivo vacío se entrega para validación por el lector', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {'name': 'vacío.csv', 'bytes': Uint8List(0)},
    );
    final result =
        await NativeLocalFileSelector(hint: LocalFileHint.xls).select()
            as LocalFileSelected;
    expect(result.bytes, isEmpty);
  });

  test('Cancelación no se confunde con un error', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(
      await NativeLocalFileSelector(hint: LocalFileHint.xls).select(),
      isA<LocalFileCancelled>(),
    );
  });

  for (final entry in {
    'accessDenied': LocalFileFailureCode.accessDenied,
    'unavailable': LocalFileFailureCode.unavailable,
    'readFailed': LocalFileFailureCode.readFailed,
    'busy': LocalFileFailureCode.busy,
    'unexpectedNativeError': LocalFileFailureCode.readFailed,
  }.entries) {
    test('Distingue ${entry.key} y permite volver a cargar', () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        if (calls++ == 0) throw PlatformException(code: entry.key);
        return null;
      });
      final selector = NativeLocalFileSelector(hint: LocalFileHint.xls);
      final result = await selector.select() as LocalFileFailed;
      expect(result.code, entry.value);
      expect(await selector.select(), isA<LocalFileCancelled>());
    });
  }

  test('Host no registrado devuelve no disponible', () async {
    final result =
        await NativeLocalFileSelector(hint: LocalFileHint.xls).select()
            as LocalFileFailed;
    expect(result.code, LocalFileFailureCode.unavailable);
  });

  test('Rechaza respuestas corruptas sin exponer rutas ni contenido', () async {
    for (final value in [
      'texto',
      <String, Object>{},
      {'name': 'C:\\privado.csv', 'bytes': Uint8List(1)},
      {'name': 'a/b.csv', 'bytes': Uint8List(1)},
      {'name': '', 'bytes': Uint8List(1)},
      {'name': 'a\u0000.csv', 'bytes': Uint8List(1)},
      {'name': 'a.csv', 'bytes': 'texto'},
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => value);
      final result =
          await NativeLocalFileSelector(hint: LocalFileHint.xls).select()
              as LocalFileFailed;
      expect(result.code, LocalFileFailureCode.readFailed);
    }
  });

  test('Una sola selección en vuelo y recuperación al cancelar', () async {
    final completion = Completer<Object?>();
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) {
      calls++;
      return completion.future;
    });
    final selector = NativeLocalFileSelector(hint: LocalFileHint.xls);
    final first = selector.select();
    final second = await selector.select() as LocalFileFailed;
    expect(second.code, LocalFileFailureCode.busy);
    completion.complete(null);
    expect(await first, isA<LocalFileCancelled>());
    expect(calls, 1);
    expect(await selector.select(), isA<LocalFileCancelled>());
    expect(calls, 2);
  });

  test('El consumidor puede inyectar un doble sin Flutter ni rutas', () async {
    final LocalFileSelector selector = _SelectorDouble();
    final result = await selector.select() as LocalFileSelected;
    expect(result.name, 'sintético.xls');
    expect(result.bytes, [65, 13, 10]);
  });
}

final class _SelectorDouble implements LocalFileSelector {
  @override
  Future<LocalFileSelection> select() async => LocalFileSelected(
    name: 'sintético.xls',
    bytes: Uint8List.fromList([65, 13, 10]),
  );
}
