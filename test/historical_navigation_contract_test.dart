import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/navigation/movement_links.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/app/navigation/session_location.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

import 'support/historical_navigation_fixture.dart';

/// Consumidores de contratos de periodo, NO informes Estado/Real/Presupuesto
/// anual/Indicadores. Ninguna prueba calcula su matriz, diferencias o colchón.
void main() {
  late HistoricalNavigationFixture data;
  late NavigationSession session;
  setUp(() async {
    data = HistoricalNavigationFixture();
    await data.seed();
    session = NavigationSession(
      clock: () => DateTime.utc(2025, 12, 31, 23, 30),
    );
  });
  tearDown(() async {
    session.dispose();
    await data.close();
  });

  test(
    'Contrato pendiente: anual conserva mes enfocado y consulta todo el año',
    () async {
      final before = await data.database.readState();
      await session.selectPeriod(NavigationPeriod(2026, 2));
      for (final destination in [
        SessionDestination.actual,
        SessionDestination.budget,
      ]) {
        await session.changeDestination(destination);
        final annual = session.context.annualPeriod;
        expect(annual.focusedMonth, 2);
        expect(annual.firstDay.value, '2026-01-01');
        expect(annual.until!.value, '2027-01-01');
        final link = MovementLinks.list(
          MovementListQuery(from: annual.firstDay, until: annual.until),
          origin: SessionLocation.encode(session.context),
        );
        final query = MovementLinks.parse(link, defaultMonth: Month(2035, 1));
        final rows = await SqliteMovementRepository(data.database)
            .list(from: query.from, until: query.until);
        expect(
          rows.map((r) => r.data.valueDate.value),
          unorderedEquals(['2026-01-01', '2026-01-15']),
        );
        expect(
          MovementLinks.origin(link),
          SessionLocation.encode(session.context),
        );
        await session.selectYear(2024);
        expect(session.period, NavigationPeriod(2024, 1));
        await session.selectPeriod(NavigationPeriod(2025, 12));
        await session.selectYear(2026);
        expect(session.period, NavigationPeriod(2026, 2));
        await session.selectYear(2025);
        expect(session.period, NavigationPeriod(2025, 12));
        await session.selectYear(2026);
      }
      await session.changeDestination(SessionDestination.status);
      await session.selectYear(2035);
      expect(session.period, NavigationPeriod(2035, 2));
      expect((await data.database.readState()).revision, before.revision);
    },
  );

  test('Contrato pendiente: entradas mensuales y retorno seguro con contexto completo', () async {
    for (final destination in [
      SessionDestination.status,
      SessionDestination.indicators,
    ]) {
      final origin = NavigationContext(
        destination: destination,
        period: NavigationPeriod(2026, 1),
        branchId: data.categoryId,
        scope: MovementCategoryScope.direct,
        filters: const {'concepto': 'Enero'},
        scrollOffset: 125,
        focus: 'celda-enero',
      );
      await session.setContext(origin);
      final detail = session.openSecondary();
      final route = SessionLocation.encode(origin);
      final resolved =
          SessionLocation.resolve(route, session) as ValidSessionLocation;
      expect(resolved.context.period, origin.period);
      expect(resolved.context.branchId, data.categoryId);
      expect(resolved.context.scope, MovementCategoryScope.direct);
      final link = MovementLinks.list(
        MovementListQuery(
          from: origin.period.firstDay,
          until: origin.period.next!.firstDay,
          categoryId: origin.branchId,
          scope: origin.scope,
          concept: origin.filters['concepto']!,
        ),
        origin: route,
      );
      final query = MovementLinks.parse(link, defaultMonth: Month(2035, 1));
      expect(query.from.value, '2026-01-01');
      expect(query.until!.value, '2026-02-01');
      expect(query.scope, MovementCategoryScope.direct);
      expect(query.concept, 'Enero');
      await session.selectPeriod(NavigationPeriod(2035, 1));
      await session.returnToOrigin(detail);
      expect(session.context, same(origin));
      expect(session.context.scrollOffset, 125);
      expect(session.context.focus, 'celda-enero');
      expect(
        SessionLocation.resolve('/estado?a=0000&m=01', session),
        isA<InvalidSessionLocation>(),
      );
      expect(session.context, same(origin));
      expect(
        () => MovementLinks.list(query, origin: 'https://example.com/estado'),
        throwsA(isA<MovementFailure>()),
      );
    }
  });

  test('Datos de contrato: cero REAL, ausencia de partida y cero explícito son distintos', () async {
    final before = await data.database.readState();
    for (final period in [
      NavigationPeriod(1980, 1),
      NavigationPeriod(2035, 1),
    ]) {
      final real = await SqliteMovementRepository(data.database)
          .readPage(from: period.firstDay, until: period.next!.firstDay);
      expect(real.records, isEmpty);
      expect(real.subtotalCents, 0);
      final budget = await data.budget.query.read(period.budgetMonth);
      expect(budget.activeTree.every((r) => r.budget == null), isTrue);
      expect(budget.archivedBudgets, isEmpty);
      final photo = await data.wealth.photos.read(period.civilMonth);
      expect(photo.status, WealthSnapshotStatus.absent);
      expect(photo.values, isEmpty);
    }
    final january = await data.budget.query.read(
      NavigationPeriod(2026, 1).budgetMonth,
    );
    final registered = january.activeTree.singleWhere(
      (r) => r.categoryId == data.categoryId,
    );
    expect(registered.ownAmountCents, 0);
    expect(registered.budget, isNotNull);
    final year = await SqliteBudgetRepository(data.database).readYear(2026);
    expect(year.map((r) => r.data.amountCents), [0, -12300]);
    expect((await data.database.readState()).revision, before.revision);
  });

  test('Contrato Indicadores: foto exacta y presupuesto del mismo año, sin cálculo', () async {
    final before = await data.database.readState();
    await session.changeDestination(SessionDestination.indicators);
    for (final (month, status, liquid) in [
      (1, WealthSnapshotStatus.incomplete, null),
      (2, WealthSnapshotStatus.complete, 0),
      (3, WealthSnapshotStatus.absent, null),
    ]) {
      await session.selectPeriod(NavigationPeriod(2026, month));
      final period = session.period;
      final photo = WealthReading.fromSnapshot(
        await data.wealth.photos.read(period.civilMonth),
      );
      final income = await SqliteBudgetRepository(data.database)
          .readYear(period.year, incomeOnly: true);
      expect(photo.month.value, '2026-0$month-01');
      expect(photo.status, status);
      expect(photo.liquidAssetsCents, liquid);
      expect(income, isEmpty); // No se inventa un resultado del colchón.
    }
    final year = await data.wealth.photos.readYear(2026);
    expect(year, hasLength(12));
    expect(year[0].status, WealthSnapshotStatus.incomplete);
    expect(year[1].status, WealthSnapshotStatus.complete);
    expect(
      year.skip(2).every((p) => p.status == WealthSnapshotStatus.absent),
      isTrue,
    );
    expect((await data.database.readState()).revision, before.revision);
  });
}
