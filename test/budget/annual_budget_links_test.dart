import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/navigation/budget_links.dart';
import 'package:myautofinance/app/navigation/budget_origin.dart';
import 'package:myautofinance/app/navigation/movement_links.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/app/navigation/session_location.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart' show Month;

const category = '00000000-0000-0000-0000-000000000001';

void main() {
  test(
    'Año completo y rango no se limitan al mes enfocado; origen completo',
    () {
      final original = BudgetOrigin(
        NavigationContext(
          destination: SessionDestination.budget,
          period: NavigationPeriod(2026, 10),
          branchId: category,
          filters: {'abiertas': category},
          scrollOffset: 345.5,
          focus: '$category:10:total',
        ),
      );
      final route = BudgetLinks.list(
        BudgetListQuery.annual(2026, focusedMonth: 10, categoryId: category),
        origin: original.route,
      );
      final query = BudgetLinks.parse(route);
      expect(query.isAnnual, isTrue);
      expect(query.month.value, '2026-10-01');
      expect(query.firstMonth.value, '2026-01-01');
      expect(query.lastMonth.value, '2026-12-01');
      expect(query.scope, MovementCategoryScope.branch);
      final returned = BudgetLinks.origin(route)!.context;
      expect(returned.period, original.context.period);
      expect(returned.view, PeriodView.annual);
      expect(returned.branchId, category);
      expect(returned.filters, original.context.filters);
      expect(returned.scrollOffset, 345.5);
      expect(returned.focus, original.context.focus);
      final range = BudgetListQuery.range(
        month: BudgetMonth(2026, 10),
        firstMonth: BudgetMonth(2026, 2),
        lastMonth: BudgetMonth(2026, 4),
      );
      final restored = BudgetLinks.parse(BudgetLinks.list(range));
      expect(restored.includesMonth(BudgetMonth(2026, 2)), isTrue);
      expect(restored.includesMonth(BudgetMonth(2026, 4)), isTrue);
      expect(restored.includesMonth(BudgetMonth(2026, 10)), isFalse);
      expect(restored.month.value, '2026-10-01');
    },
  );

  test('Captura mensual es origen permitido de Gestión; no hereda filtros', () {
    final original = BudgetOrigin(
      NavigationContext(
        destination: SessionDestination.budget,
        period: NavigationPeriod(2026, 2),
        view: PeriodView.monthly,
        branchId: category,
        filters: {'abiertas': category},
        scrollOffset: 15,
        focus: category,
      ),
    );
    expect(Uri.parse(original.route).path, '/presupuesto/mensual');
    final movements = MovementLinks.management(
      original.route,
      defaultMonth: Month(2030, 1),
    );
    final query = MovementLinks.parse(movements, defaultMonth: Month(2030, 1));
    expect(query.from.value, '2026-02-01');
    expect(query.categoryId, isNull);
    expect(MovementLinks.origin(movements), original.route);
    expect(BudgetOrigin.parse(original.route).context.view, PeriodView.monthly);
  });

  test(
    'Presupuesto principal aplica memoria anual; cambiar destino conserva foco',
    () async {
      final session = NavigationSession(
        initialContext: NavigationContext(
          destination: SessionDestination.status,
          period: NavigationPeriod(2026, 10),
        ),
      );
      addTearDown(session.dispose);
      await session.selectPeriod(NavigationPeriod(2025, 7));
      await session.selectPeriod(NavigationPeriod(2026, 10));
      final implicit = SessionLocation.resolve(
        '/presupuesto',
        session,
      ) as ValidSessionLocation;
      expect(implicit.context.view, PeriodView.annual);
      expect(implicit.context.period, NavigationPeriod(2026, 10));
      final alias = SessionLocation.resolve(
        '/presupuesto?a=2026&m=10&c=$category&alcance=direct',
        session,
      ) as ValidSessionLocation;
      expect(alias.context.branchId, category);
      expect(alias.context.scope, MovementCategoryScope.direct);
      final remembered = SessionLocation.resolve(
        '/presupuesto?a=2025',
        session,
      ) as ValidSessionLocation;
      expect(remembered.context.period, NavigationPeriod(2025, 7));
      final unknown = SessionLocation.resolve(
        '/presupuesto?a=2035',
        session,
      ) as ValidSessionLocation;
      expect(unknown.context.period, NavigationPeriod(2035, 1));
      expect(session.period, NavigationPeriod(2026, 10));
    },
  );

  test('Links y orígenes inválidos rechazan ambigüedad sin ampliar el alcance', () {
    for (final suffix in [
      '&desde=01',
      '&hasta=12',
      '&desde=00&hasta=12',
      '&desde=11&hasta=02',
      '&desde=1&hasta=12',
      '&desde=01&desde=02&hasta=12',
      '&cuenta=$category',
      '&origen=${Uri.encodeComponent('/presupuesto?a=2026&m=10&posicion=NaN')}',
      '&origen=${Uri.encodeComponent('/presupuesto?a=2026&m=10&origen=/estado')}',
    ]) {
      expect(
        () => BudgetLinks.parse('/presupuesto/partidas?a=2026&m=10$suffix'),
        throwsException,
      );
    }
    for (final route in [
      'https://example.com/presupuesto?a=2026&m=10',
      '//example.com/presupuesto?a=2026&m=10',
      '/presupuesto?a=0000&m=10',
      '/presupuesto?a=2026&m=10&m=11',
      '/presupuesto?a=2026&m=10&rama=nombre',
      '/presupuesto?a=2026&m=10&posicion=-1',
      '/presupuesto?a=2026&m=10&abiertas=nombre',
      '/presupuesto?a=2026&m=10&foco=%0A',
      '/presupuesto/propuesta?a=2026&m=10',
    ]) {
      expect(() => BudgetOrigin.parse(route), throwsException, reason: route);
    }
    expect(
      () => BudgetListQuery.range(
        month: BudgetMonth(2026, 1),
        firstMonth: BudgetMonth(2027, 1),
        lastMonth: BudgetMonth(2026, 12),
      ),
      throwsException,
    );
  });
}
