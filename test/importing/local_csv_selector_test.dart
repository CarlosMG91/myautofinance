import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/local_csv_selector_factory.dart';
import 'package:myautofinance/features/importing/data/native_local_csv_selector.dart';
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
    expect(createLocalCsvSelector(), isA<LocalCsvSelector>());
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
      expect(call.arguments, isNull);
      return {'name': 'histórico.txt', 'bytes': original};
    });
    final result = await NativeLocalCsvSelector().select() as LocalCsvSelected;
    expect(result.name, 'histórico.txt');
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
    final result = await NativeLocalCsvSelector().select() as LocalCsvSelected;
    expect(result.bytes, isEmpty);
  });

  test('Cancelación no se confunde con un error', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await NativeLocalCsvSelector().select(), isA<LocalCsvCancelled>());
  });

  for (final entry in {
    'accessDenied': LocalCsvFailureCode.accessDenied,
    'unavailable': LocalCsvFailureCode.unavailable,
    'readFailed': LocalCsvFailureCode.readFailed,
    'busy': LocalCsvFailureCode.busy,
    'unexpectedNativeError': LocalCsvFailureCode.readFailed,
  }.entries) {
    test('Distingue ${entry.key} y permite volver a cargar', () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        if (calls++ == 0) throw PlatformException(code: entry.key);
        return null;
      });
      final selector = NativeLocalCsvSelector();
      final result = await selector.select() as LocalCsvFailed;
      expect(result.code, entry.value);
      expect(await selector.select(), isA<LocalCsvCancelled>());
    });
  }

  test('Host no registrado devuelve no disponible', () async {
    final result = await NativeLocalCsvSelector().select() as LocalCsvFailed;
    expect(result.code, LocalCsvFailureCode.unavailable);
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
      final result = await NativeLocalCsvSelector().select() as LocalCsvFailed;
      expect(result.code, LocalCsvFailureCode.readFailed);
    }
  });

  test('Una sola selección en vuelo y recuperación al cancelar', () async {
    final completion = Completer<Object?>();
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) {
      calls++;
      return completion.future;
    });
    final selector = NativeLocalCsvSelector();
    final first = selector.select();
    final second = await selector.select() as LocalCsvFailed;
    expect(second.code, LocalCsvFailureCode.busy);
    completion.complete(null);
    expect(await first, isA<LocalCsvCancelled>());
    expect(calls, 1);
    expect(await selector.select(), isA<LocalCsvCancelled>());
    expect(calls, 2);
  });

  test('El consumidor puede inyectar un doble sin Flutter ni rutas', () async {
    final LocalCsvSelector selector = _SelectorDouble();
    final result = await selector.select() as LocalCsvSelected;
    expect(result.name, 'sintético.csv');
    expect(result.bytes, [65, 13, 10]);
  });
}

final class _SelectorDouble implements LocalCsvSelector {
  @override
  Future<LocalCsvSelection> select() async => LocalCsvSelected(
    name: 'sintético.csv',
    bytes: Uint8List.fromList([65, 13, 10]),
  );
}
