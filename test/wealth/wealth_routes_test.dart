import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/navigation/wealth_route.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  final fallback = Month(2026, 10);
  WealthRoute parse(String route) =>
      WealthRoute.parse(route, defaultMonth: fallback);
  test('Rutas aprobadas separan foto, catálogo, alta y detalle por ID', () {
    expect(parse('/patrimonio?a=2026&m=02').month!.value, '2026-02-01');
    expect(parse('/patrimonio').month!.value, fallback.value);
    expect(
      parse('/patrimonio/foto?a=2025&m=01&origen=indicadores').kind,
      WealthRouteKind.photo,
    );
    expect(parse('/patrimonio/fichas').kind, WealthRouteKind.catalog);
    expect(
      parse('/patrimonio/fichas/nueva').kind,
      WealthRouteKind.createAccount,
    );
    expect(
      parse('/patrimonio/fichas/identidad-estable').accountId,
      'identidad-estable',
    );
    for (final route in [
      '/patrimonio?a=0&m=01',
      '/patrimonio?a=2026&m=13',
      '/patrimonio?a=no&m=02',
      '/patrimonio/foto?a=2026&m=2',
      '/patrimonio/fichas/id/extra',
      '/patrimonio/desconocida',
    ]) {
      expect(() => parse(route), throwsA(isA<AccountFailure>()));
    }
  });
  test('Mes Europe/Madrid respeta cambios de mes de invierno y verano', () {
    expect(
      madridMonth(DateTime.parse('2026-01-31T23:30:00Z')).value,
      '2026-02-01',
    );
    expect(
      madridMonth(DateTime.parse('2026-06-30T22:30:00Z')).value,
      '2026-07-01',
    );
    expect(
      madridMonth(DateTime.parse('2026-10-31T22:30:00Z')).value,
      '2026-10-01',
    );
  });
}
