import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/navigation/budget_links.dart';
import 'package:myautofinance/app/navigation/monthly_status_origin.dart';
import 'package:myautofinance/app/navigation/movement_links.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/monthly_status/monthly_status.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  const id = '00000000-0000-0000-0000-000000000001';
  final origin = MonthlyStatusOrigin(
    NavigationContext(
      destination: SessionDestination.status,
      period: NavigationPeriod(2026, 1),
      branchId: id,
      scope: MovementCategoryScope.direct,
      filters: {'abiertas': id},
      scrollOffset: 412.5,
      focus: '$id:real-directo',
    ),
  );
  test('Links mensuales independientes de consulta conservan contexto seguro completo', () {
    final detail = MonthlyFigureDetail(
      month: BudgetMonth(2026, 1),
      categoryId: id,
    );
    final real = MovementLinks.list(detail.movements, origin: origin.route);
    final planned = BudgetLinks.list(detail.budgets, origin: origin.route);
    expect(
      MovementLinks.parse(real, defaultMonth: Month(2026, 10)).categoryId,
      id,
    );
    expect(BudgetLinks.parse(planned).categoryId, id);
    for (final route in [
      MovementLinks.origin(real)!,
      BudgetLinks.origin(planned)!.route,
    ]) {
      final parsed = MonthlyStatusOrigin.parse(route).context;
      expect(parsed.period, origin.context.period);
      expect(parsed.branchId, id);
      expect(parsed.scope, MovementCategoryScope.direct);
      expect(parsed.filters, origin.context.filters);
      expect(parsed.scrollOffset, 412.5);
      expect(parsed.focus, '$id:real-directo');
    }
    expect(
      Uri.parse(BudgetLinks.create(detail.budgets, origin: origin.route)).path,
      '/presupuesto/partidas/nueva',
    );
    expect(
      Uri.parse(BudgetLinks.detail(id, detail.budgets, origin: origin.route))
          .path,
      '/presupuesto/partidas/$id',
    );
  });
  test(
    'Total y Sin clasificar no se confunden; directo y rama se serializan',
    () {
      for (final scope in MovementCategoryScope.values) {
        final total = MonthlyFigureDetail(
          month: BudgetMonth(2026, 1),
          scope: scope,
        );
        expect(
          BudgetLinks.parse(BudgetLinks.list(total.budgets)).unclassified,
          isFalse,
        );
        final nulls = MonthlyFigureDetail(
          month: total.month,
          scope: scope,
          unclassified: true,
        );
        final parsed = BudgetLinks.parse(BudgetLinks.list(nulls.budgets));
        expect(parsed.categoryId, isNull);
        expect(parsed.unclassified, isTrue);
        expect(parsed.scope, scope);
      }
    },
  );
  test('Origen inválido o ambiguo se rechaza sin sesión o lector', () {
    for (final route in [
      'https://example.com/estado?a=2026&m=01',
      '/estado?a=2026&m=01#foco',
      '/estado?a=2026&m=01&a=2027',
      '/estado?a=0000&m=01',
      '/estado?a=2026',
      '/estado?a=2026&m=01&rama=nombre',
      '/estado?a=2026&m=01&posicion=NaN',
      '/estado?a=2026&m=01&posicion=-1',
      '/estado?a=2026&m=01&abiertas=nombre',
      '/estado?a=2026&m=01&origen=%2Freal',
      '/real?a=2026&m=01',
    ]) {
      expect(
        () => MonthlyStatusOrigin.parse(route),
        throwsException,
        reason: route,
      );
    }
  });
  test('Ruta de partidas inválida o ambigua se rechaza antes de consultar', () {
    for (final route in [
      '/presupuesto/partidas?a=2026',
      '/presupuesto/partidas?a=2026&m=1',
      '/presupuesto/partidas?a=2026&m=01&rama=$id&c=$id',
      '/presupuesto/partidas?a=2026&m=01&rama=nombre',
      '/presupuesto/partidas?a=2026&m=01&alcance=otro',
      '/presupuesto/partidas?a=2026&m=01&m=02',
      '/presupuesto/partidas?a=2026&m=01&origen=https%3A%2F%2Fexample.com',
    ]) {
      expect(() => BudgetLinks.parse(route), throwsException, reason: route);
    }
    expect(
      MovementLinks.parse(
        '/movimientos?a=2026&m=01&desde=2026-02-01&hasta=2026-03-01',
        defaultMonth: Month(2026, 1),
      ).from.value,
      '2026-02-01',
    );
  });
}
