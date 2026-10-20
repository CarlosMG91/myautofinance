import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../scripts/fixtures/android-upgrade/main.dart' as fixture;

void main() {
  test('proveedor del ensayo conserva JSON UTF-8 en GET y POST', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final received = <Object?>[];
    final subscription = server.listen((request) async {
      expect(request.headers.value('X-Upgrade-Token'), 'synthetic-test-value');
      if (request.method == 'POST') {
        received.add(jsonDecode(await utf8.decoder.bind(request).join()));
      }
      request.response.add(
        utf8.encode(jsonEncode({'csv': 'Café;Discrecionalidad;€'})),
      );
      await request.response.close();
    });
    try {
      final uri = Uri.parse('http://127.0.0.1:${server.port}/fixture');
      final command = await fixture.exchangeAt(uri, 'synthetic-test-value');
      expect(command['csv'], 'Café;Discrecionalidad;€');
      final result = await fixture.exchangeAt(
        uri,
        'synthetic-test-value',
        body: {'error': 'Restauración pendiente: café y €'},
      );
      expect(result['csv'], command['csv']);
      expect(received, [
        {'error': 'Restauración pendiente: café y €'},
      ]);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
