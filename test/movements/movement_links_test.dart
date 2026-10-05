import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/navigation/movement_links.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  const id = '00000000-0000-0000-0000-000000000001';
  final current = Month(2026, 10);
  test('Enlace de informe conserva rango, UUID, alcance, cuenta, búsqueda y origen', () {
    final query = MovementListQuery(
      from: ValueDate(2026, 1, 1),
      until: ValueDate(2027, 1, 1),
      categoryId: id,
      scope: MovementCategoryScope.direct,
      accountId: id,
      concept: 'CAFÉ & árbol',
    );
    const origin = '/real?a=2026&m=03&rama=$id&alcance=directo';
    final link = MovementLinks.list(query, origin: origin);
    final parsed = MovementLinks.parse(link, defaultMonth: current);
    expect(parsed.from.value, query.from.value);
    expect(parsed.until!.value, query.until!.value);
    expect(parsed.categoryId, id);
    expect(parsed.accountId, id);
    expect(parsed.scope, MovementCategoryScope.direct);
    expect(parsed.concept, query.concept);
    expect(MovementLinks.origin(link), origin);
    expect(
      Uri.parse(MovementLinks.create(query, origin: origin)).path,
      '/movimientos/nuevo',
    );
    expect(
      Uri.parse(MovementLinks.detail(id, query, origin: origin)).path,
      '/movimientos/$id',
    );
  });
  test('Sin clasificar, aliases anteriores y extremo calendario', () {
    final q = MovementLinks.parse(
      '/movimientos?a=2026&m=03&rama=sin-clasificar',
      defaultMonth: current,
    );
    expect(q.unclassified, isTrue);
    expect(q.categoryId, isNull);
    expect(
      MovementLinks.parse(
        '/movimientos?a=2026&m=03&c=$id&alcance=branch',
        defaultMonth: current,
      ).categoryId,
      id,
    );
    final last = MovementLinks.parse(
      '/movimientos?a=9999&m=12',
      defaultMonth: current,
    );
    expect(last.until, isNull);
    expect(
      MovementLinks.parse(
        MovementLinks.list(last),
        defaultMonth: current,
      ).from.value,
      '9999-12-01',
    );
  });
  test('Gestión solo hereda el mes seleccionado', () {
    final link = MovementLinks.management(
      '/estado?a=2026&m=03&rama=$id&alcance=directo',
      defaultMonth: current,
    );
    final query = MovementLinks.parse(link, defaultMonth: current);
    expect(query.from.value, '2026-03-01');
    expect(query.until!.value, '2026-04-01');
    expect(query.categoryId, isNull);
    expect(query.scope, MovementCategoryScope.branch);
  });
  test('Rutas ambiguas o externas se rechazan antes de consultar', () {
    for (final link in [
      '/movimientos?a=2026',
      '/movimientos?a=2026&m=3',
      '/movimientos?a=2026&m=13',
      '/movimientos?desde=2026-04-01&hasta=2026-03-01',
      '/movimientos?a=2026&m=03&c=$id&rama=$id',
      '/movimientos?a=2026&m=03&c=$id&sinClasificar=1',
      '/movimientos?a=2026&m=03&alcance=desconocido',
      '/movimientos?a=2026&m=03&a=2027',
      '/movimientos?a=2026&m=03&origen=https%3A%2F%2Fexample.com',
    ]) {
      expect(
        () => MovementLinks.parse(link, defaultMonth: current),
        throwsException,
        reason: link,
      );
    }
  });
}
