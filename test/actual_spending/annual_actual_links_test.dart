import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/navigation/annual_actual_origin.dart';
import 'package:myautofinance/app/navigation/movement_links.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/features/actual_spending/actual_spending.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  const id = '00000000-0000-0000-0000-000000000001';
  final defaultMonth = Month(2026, 10);
  test(
    'Total general solo identifica un despliegue de meses, nunca una categoría',
    () {
      for (final context in [
        NavigationContext(
          destination: SessionDestination.actual,
          period: NavigationPeriod(2026, 2),
          branchId: 'total-general',
        ),
        NavigationContext(
          destination: SessionDestination.actual,
          period: NavigationPeriod(2026, 2),
          filters: {'abiertas': 'total-general'},
        ),
      ]) {
        expect(() => AnnualActualOrigin(context), throwsException);
      }
    },
  );
  test('Contrato independiente: año/mes, rama/directo, total y NULL', () {
    for (final year in [1, 2024, 2026, 9999]) {
      for (final month in [null, 1, 2, 12]) {
        for (final category in [null, id, 'sin-clasificar']) {
          for (final scope in MovementCategoryScope.values) {
            final detail = AnnualActualDetail(
              year: year,
              month: month,
              categoryId: category == 'sin-clasificar' ? null : category,
              unclassified: category == 'sin-clasificar',
              scope: scope,
            );
            final parsed = MovementLinks.parse(
              MovementLinks.list(detail.movements),
              defaultMonth: defaultMonth,
            );
            expect(parsed.from.value, ValueDate(year, month ?? 1, 1).value);
            expect(parsed.until?.value, detail.movements.until?.value);
            expect(
              parsed.until == null,
              year == 9999 && (month == null || month == 12),
            );
            expect(parsed.categoryId, detail.categoryId);
            expect(parsed.unclassified, detail.unclassified);
            expect(parsed.scope, scope);
            expect(parsed.accountId, isNull);
            expect(parsed.concept, isEmpty);
          }
        }
      }
    }
    expect(
      AnnualActualDetail(year: 2024, month: 2).movements.until!.value,
      '2024-03-01',
    );
    expect(AnnualActualDetail(year: 2026).movements.until!.value, '2027-01-01');
    for (final year in [0, 10000]) {
      expect(() => AnnualActualDetail(year: year), throwsException);
    }
    for (final month in [0, 13]) {
      expect(
        () => AnnualActualDetail(year: 2026, month: month),
        throwsException,
      );
    }
    expect(
      () => AnnualActualDetail(year: 2026, categoryId: id, unclassified: true),
      throwsException,
    );
  });
  test('Resumen/detalle conserva todo el contexto en lista/alta/editor', () {
    for (final detail in [false, true]) {
      final original = AnnualActualOrigin(
        NavigationContext(
          destination: SessionDestination.actual,
          period: NavigationPeriod(9999, 12),
          branchId: 'sin-clasificar',
          scope: MovementCategoryScope.direct,
          filters: {
            'abiertas': id,
            'meses': '$id,sin-clasificar,total-general',
          },
          scrollOffset: 123.5,
          focus: '$id:anual',
        ),
        detail: detail,
      );
      final saved = AnnualActualOrigin.parse(original.route);
      expect(saved.detail, detail);
      expect(saved.context.period, original.context.period);
      expect(saved.context.filters, original.context.filters);
      expect(saved.context.scrollOffset, 123.5);
      expect(saved.context.focus, original.context.focus);
      expect(saved.context.branchId, 'sin-clasificar');
      final query = AnnualActualDetail(year: 9999).movements;
      for (final route in [
        MovementLinks.list(query, origin: saved.route),
        MovementLinks.create(query, origin: saved.route),
        MovementLinks.detail(id, query, origin: saved.route),
      ]) {
        expect(MovementLinks.origin(route), saved.route);
      }
    }
  });
  test('Origen inválido y rutas ambiguas se rechazan antes de leer', () {
    for (final route in [
      '/real?a=0000&m=01',
      '/real?a=10000&m=01',
      '/real?a=2026&m=13',
      '/real?a=2026&m=01&a=2027',
      '/real?a=2026&m=01&rama=incorrecto',
      '/real?a=2026&m=01&abiertas=incorrecto',
      '/real?a=2026&m=01&meses=incorrecto',
      '/real?a=2026&m=01&posicion=NaN',
      '/real?a=2026&m=01&posicion=-1',
      '/real?a=2026&m=01&foco=%00',
      '/real?a=2026&m=01&alcance=otro',
      '/real?a=2026&m=01&origen=/inicio',
      'https://example.com/real?a=2026&m=01',
      '/real/detalle?a=2026&m=01#fragmento',
    ]) {
      expect(
        () => MovementLinks.list(
          AnnualActualDetail(year: 2026).movements,
          origin: route,
        ),
        throwsException,
        reason: route,
      );
      final link = Uri(
        path: '/movimientos',
        queryParameters: {
          'desde': '2026-01-01',
          'hasta': '2027-01-01',
          'origen': route,
        },
      ).toString();
      expect(
        () => MovementLinks.parse(link, defaultMonth: defaultMonth),
        throwsException,
        reason: route,
      );
    }
  });
}
