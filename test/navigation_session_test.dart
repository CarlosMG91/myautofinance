import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/navigation/app_router.dart';
import 'package:myautofinance/app/navigation/app_routes.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/app/navigation/navigation_session_scope.dart';
import 'package:myautofinance/app/navigation/session_location.dart';
import 'package:myautofinance/features/movements/movements.dart';

NavigationSession sessionAt(int year, int month) =>
    NavigationSession(clock: () => DateTime.utc(year, month, 15));

void main() {
  test('Periodo reutiliza tipos civiles y valida todo el rango', () {
    final first = NavigationPeriod(1, 1);
    final last = NavigationPeriod(9999, 12);
    expect(first.toString(), '0001-01');
    expect(first.previous, isNull);
    expect(first.next, NavigationPeriod(1, 2));
    expect(last.next, isNull);
    expect(last.previous, NavigationPeriod(9999, 11));
    expect(last.budgetMonth.value, '9999-12-01');
    expect(last.firstDay.value, '9999-12-01');
    for (final (year, month) in [(0, 1), (10000, 1), (1, 0), (1, 13)]) {
      expect(() => NavigationPeriod(year, month), throwsA(isA<Exception>()));
    }
    expect(NavigationPeriod(2024, 12).next, NavigationPeriod(2025, 1));
    expect(NavigationPeriod(2025, 1).previous, NavigationPeriod(2024, 12));
    for (final month in [2, 3, 10]) {
      expect(
        NavigationPeriod(2024, month).next!.firstDay.value,
        '2024-${(month + 1).toString().padLeft(2, '0')}-01',
      );
    }
  });

  test(
    'El año anual expone enero y conserva un foco mensual independiente',
    () {
      final annual = AnnualNavigationPeriod(NavigationPeriod(2024, 2));
      expect(annual.year, 2024);
      expect(annual.focusedMonth, 2);
      expect(annual.firstDay.value, '2024-01-01');
      expect(annual.until!.value, '2025-01-01');
      expect(annual.focusedPeriod.firstDay.value, '2024-02-01');
      expect(AnnualNavigationPeriod(NavigationPeriod(9999, 8)).until, isNull);
    },
  );

  for (final (instant, expected) in [
    ('2026-01-31T23:30:00Z', '2026-02'),
    ('2026-06-30T22:30:00Z', '2026-07'),
    ('2026-03-29T00:59:59Z', '2026-03'),
    ('2026-03-29T01:00:00Z', '2026-03'),
    ('2026-10-25T00:59:59Z', '2026-10'),
    ('2026-10-25T01:00:00Z', '2026-10'),
    ('2026-12-31T23:30:00Z', '2027-01'),
  ]) {
    test('Nueva sesión usa Europe/Madrid en $instant', () {
      final session = NavigationSession(clock: () => DateTime.parse(instant));
      addTearDown(session.dispose);
      expect(session.context.destination, SessionDestination.status);
      expect(session.period.toString(), expected);
    });
  }

  test(
    'Elección explícita prevalece hasta Mes actual; reinicio no hereda memoria',
    () async {
      var instant = DateTime.utc(2026, 6, 15);
      var reads = 0;
      DateTime clock() {
        reads++;
        return instant;
      }

      final session = NavigationSession(clock: clock);
      addTearDown(session.dispose);
      await session.selectPeriod(NavigationPeriod(1998, 11));
      instant = DateTime.utc(2027, 2, 15);
      for (final destination in SessionDestination.values) {
        await session.changeDestination(destination);
        expect(session.period, NavigationPeriod(1998, 11));
      }
      expect(reads, 1);
      await session.currentMonth();
      expect(session.period, NavigationPeriod(2027, 2));
      expect(reads, 2);
      final fresh = NavigationSession(clock: clock);
      addTearDown(fresh.dispose);
      expect(fresh.context.destination, SessionDestination.status);
      expect(fresh.period, NavigationPeriod(2027, 2));
      expect(fresh.rememberedMonth(1998), isNull);
      final explicit = NavigationSession(
        clock: () => throw StateError('No leer'),
        initialContext: NavigationContext(
          destination: SessionDestination.wealth,
          period: NavigationPeriod(2030, 9),
        ),
      );
      addTearDown(explicit.dispose);
      expect(explicit.period, NavigationPeriod(2030, 9));
    },
  );

  test(
    'Año mensual mantiene mes; anual recupera mes del año o enero',
    () async {
      final session = sessionAt(2026, 7);
      addTearDown(session.dispose);
      await session.selectYear(2024);
      expect(session.period, NavigationPeriod(2024, 7));
      await session.selectPeriod(NavigationPeriod(2024, 11));
      await session.changeDestination(SessionDestination.actual);
      await session.selectYear(2025);
      expect(session.period, NavigationPeriod(2025, 1));
      await session.selectPeriod(NavigationPeriod(2025, 3));
      await session.selectYear(2024);
      expect(session.period, NavigationPeriod(2024, 11));
      await session.next();
      expect(session.period, NavigationPeriod(2025, 3));
      await session.previous();
      expect(session.period, NavigationPeriod(2024, 11));
      await session.changeDestination(SessionDestination.wealth);
      await session.selectYear(2026);
      expect(session.period, NavigationPeriod(2026, 11));
    },
  );

  test(
    'Límites de controles mensuales y anuales son operaciones sin cambios',
    () async {
      final session = sessionAt(2026, 7);
      addTearDown(session.dispose);
      var notifications = 0;
      session.addListener(() {
        notifications++;
      });
      await session.selectPeriod(NavigationPeriod(1, 1));
      expect(await session.previous(), isFalse);
      expect(notifications, 1);
      await session.selectPeriod(NavigationPeriod(9999, 12));
      expect(await session.next(), isFalse);
      await session.changeDestination(SessionDestination.actual);
      expect(await session.next(), isFalse);
      await session.selectPeriod(NavigationPeriod(1, 8));
      expect(await session.previous(), isFalse);
      expect(session.period, NavigationPeriod(1, 8));
    },
  );

  test(
    'Detalle devuelve instantánea con rama, alcance, filtros, scroll y foco',
    () async {
      final filters = {
        'cuenta': 'sintetica',
        'concepto': 'Compra',
        'desde': '2024-02-29',
        'hasta': '2024-04-01',
      };
      final origin = NavigationContext(
        destination: SessionDestination.actual,
        period: NavigationPeriod(2024, 2),
        branchId: 'rama-sintetica',
        scope: MovementCategoryScope.direct,
        filters: filters,
        scrollOffset: 420,
        focus: 'celda-febrero',
      );
      final session = NavigationSession(initialContext: origin);
      addTearDown(session.dispose);
      filters['concepto'] = 'Modificado';
      expect(origin.filters['concepto'], 'Compra');
      expect(() => origin.filters['concepto'] = 'Otro', throwsUnsupportedError);
      final detail = session.openSecondary();
      expect(session.context, same(origin));
      await session.returnToOrigin(detail);
      expect(session.context, same(origin));
      expect(session.context.scrollOffset, 420);
      expect(session.context.focus, 'celda-febrero');
      expect(session.context.scope, MovementCategoryScope.direct);
      expect(session.context.branchId, 'rama-sintetica');
      await session.selectPeriod(NavigationPeriod(2024, 3));
      expect(session.context.scrollOffset, 0);
      expect(session.context.focus, isNull);
      expect(session.context.filters, origin.filters);
      for (final offset in [-1.0, double.nan, double.infinity]) {
        expect(
          () => NavigationContext(
            destination: SessionDestination.status,
            period: NavigationPeriod(2024, 1),
            scrollOffset: offset,
          ),
          throwsArgumentError,
        );
      }
    },
  );

  test('Cancelación y guard tardío conservan periodo y memoria', () async {
    final session = sessionAt(2026, 7);
    addTearDown(session.dispose);
    final origin = session.context;
    expect(await session.selectYear(2030, guard: () async => false), isFalse);
    expect(session.context, same(origin));
    expect(session.rememberedMonth(2030), isNull);
    final confirmation = Completer<bool>();
    final pending = session.selectPeriod(
      NavigationPeriod(2030, 9),
      guard: () => confirmation.future,
    );
    await session.selectPeriod(NavigationPeriod(2024, 5));
    confirmation.complete(true);
    expect(await pending, isFalse);
    expect(session.period, NavigationPeriod(2024, 5));
    expect(session.rememberedMonth(2030), isNull);
    expect(
      await session.changeDestination(
        SessionDestination.budget,
        guard: () async => true,
      ),
      isTrue,
    );
  });

  test(
    'Rutas explícitas y anuales se resuelven sin modificar estado',
    () async {
      final session = sessionAt(2026, 7);
      addTearDown(session.dispose);
      await session.selectPeriod(NavigationPeriod(2024, 11));
      await session.selectPeriod(NavigationPeriod(2026, 7));
      final origin = session.context;
      final explicit = SessionLocation.resolve(
        '/real?a=2030&m=09',
        session,
      ) as ValidSessionLocation;
      expect(explicit.context.period, NavigationPeriod(2030, 9));
      expect(explicit.context.annualPeriod.focusedMonth, 9);
      expect(SessionLocation.encode(explicit.context), '/real?a=2030&m=09');
      expect(
        (SessionLocation.resolve(
          '/real?a=2024',
          session,
        ) as ValidSessionLocation).context.period,
        NavigationPeriod(2024, 11),
      );
      expect(
        (SessionLocation.resolve(
          '/real?a=2025',
          session,
        ) as ValidSessionLocation).context.period,
        NavigationPeriod(2025, 1),
      );
      expect(
        (SessionLocation.resolve(
          '/estado?a=2025',
          session,
        ) as ValidSessionLocation).context.period,
        NavigationPeriod(2025, 7),
      );
      expect(
        (SessionLocation.resolve(
          '/indicadores',
          session,
        ) as ValidSessionLocation).context.period,
        NavigationPeriod(2026, 7),
      );
      expect(session.context, same(origin));
      expect(session.rememberedMonth(2030), isNull);
    },
  );

  test('Una confirmación pendiente no modifica una sesión terminada', () async {
    final session = sessionAt(2026, 7);
    final confirmation = Completer<bool>();
    final pending = session.selectPeriod(
      NavigationPeriod(2027, 3),
      guard: () => confirmation.future,
    );
    session.dispose();
    confirmation.complete(true);
    expect(await pending, isFalse);
    expect(session.period, NavigationPeriod(2026, 7));
  });

  test('Rutas previas conservan rama, alcance y filtros opacos', () {
    final session = sessionAt(2026, 7);
    addTearDown(session.dispose);
    final result = SessionLocation.resolve(
      '/real?a=2024&m=2&rama=rama-sintetica&alcance=directo&filtro=retencion',
      session,
    ) as ValidSessionLocation;
    expect(result.context.period, NavigationPeriod(2024, 2));
    expect(result.context.branchId, 'rama-sintetica');
    expect(result.context.scope, MovementCategoryScope.direct);
    expect(result.context.filters, {'filtro': 'retencion'});
    final roundTrip = SessionLocation.resolve(
      SessionLocation.encode(result.context),
      session,
    ) as ValidSessionLocation;
    expect(roundTrip.context.period, result.context.period);
    expect(roundTrip.context.branchId, result.context.branchId);
    expect(roundTrip.context.scope, result.context.scope);
    expect(roundTrip.context.filters, result.context.filters);
  });

  for (final route in [
    '/real?a=0000',
    '/estado?a=10000&m=01',
    '/estado?a=2026&m=00',
    '/estado?a=2026&m=13',
    '/real?a=26',
    '/estado?m=01',
    '/estado?a=2026&a=2027&m=01',
    '/estado?a=2026&m=001',
    '/estado?a=2026&m=01&m=02',
    '/estado#fragmento',
    'https://example.com/estado?a=2026&m=01',
    '//example.com/estado',
    '/estado?alcance=invalido',
    '/estado?rama=uno&c=dos',
    '/estado?a=%',
    '/desconocida',
  ]) {
    test('Ruta inválida conserva origen seguro: $route', () {
      final session = sessionAt(2026, 7);
      addTearDown(session.dispose);
      final origin = session.context;
      final result =
          SessionLocation.resolve(route, session) as InvalidSessionLocation;
      expect(result.origin, same(origin));
      expect(session.context, same(origin));
      expect(result.message, 'Periodo o destino de navegación inválido.');
    });
  }

  testWidgets(
    'App conserva sesión en reconstrucción y destinos sin parámetros',
    (tester) async {
      var now = DateTime.utc(2026, 6, 30, 22, 30);
      DateTime clock() => now;
      await tester.pumpWidget(AutofinanceApp(navigationClock: clock));
      final session = NavigationSessionScope.of(
        tester.element(find.byType(Navigator)),
      );
      expect(session.context.destination, SessionDestination.status);
      expect(session.period, NavigationPeriod(2026, 7));
      expect(
        ModalRoute.of(tester.element(find.text('Estado del mes')))!
            .settings
            .name,
        '/estado?a=2026&m=07',
      );
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pushNamed('/real?a=2024&m=02');
      await tester.pumpAndSettle();
      expect(session.period, NavigationPeriod(2024, 2));
      now = DateTime.utc(2027, 8, 15);
      await tester.pumpWidget(AutofinanceApp(navigationClock: clock));
      expect(
        NavigationSessionScope.of(tester.element(find.byType(Navigator))),
        same(session),
      );
      expect(session.period, NavigationPeriod(2024, 2));
      navigator.pushReplacementNamed('/indicadores');
      await tester.pumpAndSettle();
      expect(session.period, NavigationPeriod(2024, 2));
      expect(session.context.destination, SessionDestination.indicators);
      navigator.pushNamed('/categorias');
      await tester.pumpAndSettle();
      expect(session.period, NavigationPeriod(2024, 2));
      navigator.pop();
      await tester.pumpAndSettle();
      expect(session.context.destination, SessionDestination.indicators);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(AutofinanceApp(navigationClock: clock));
      final fresh = NavigationSessionScope.of(
        tester.element(find.byType(Navigator)),
      );
      expect(fresh.period, NavigationPeriod(2027, 8));
      expect(fresh.context.destination, SessionDestination.status);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Ruta inválida no carga datos y devuelve origen completo sin pila',
    (tester) async {
      final origin = NavigationContext(
        destination: SessionDestination.wealth,
        period: NavigationPeriod(2024, 2),
        filters: {'tipo': 'cuentas'},
        scrollOffset: 70,
        focus: 'cuenta-sintetica',
      );
      final session = NavigationSession(initialContext: origin);
      addTearDown(session.dispose);
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [NavigationSessionObserver(session)],
          onGenerateInitialRoutes: (_) => [
            AppRouter.generateRoute(
              const RouteSettings(name: '${AppRoutes.wealth}?a=2026&m=13'),
              navigationSession: session,
              wealth: () async {
                calls++;
                throw StateError('No consultar');
              },
            ),
          ],
          onGenerateRoute: (settings) =>
              AppRouter.generateRoute(settings, navigationSession: session),
        ),
      );
      expect(find.text('Error de navegación'), findsOneWidget);
      expect(calls, 0);
      expect(session.context, same(origin));
      await tester.tap(find.text('Volver al origen'));
      await tester.pumpAndSettle();
      expect(session.context, same(origin));
      expect(find.text('Marcador técnico · /patrimonio'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Pop de detalle conserva contexto y pop principal restaura origen',
    (tester) async {
      final session = sessionAt(2026, 7);
      addTearDown(session.dispose);
      await tester.pumpWidget(AutofinanceApp(navigationSession: session));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pushNamed('/real?a=2024&m=02');
      await tester.pumpAndSettle();
      final origin = NavigationContext(
        destination: SessionDestination.actual,
        period: session.period,
        branchId: 'rama',
        scrollOffset: 45,
        focus: 'celda',
      );
      await session.setContext(origin);
      navigator.pushNamed('/categorias');
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();
      expect(session.context, same(origin));
      navigator.pushNamed('/estado?a=2025&m=08');
      await tester.pumpAndSettle();
      expect(session.period, NavigationPeriod(2025, 8));
      navigator.pop();
      await tester.pumpAndSettle();
      expect(session.context, same(origin));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Destino desconocido sin historial vuelve al contexto de sesión',
    (tester) async {
      final origin = NavigationContext(
        destination: SessionDestination.actual,
        period: NavigationPeriod(2024, 9),
        branchId: 'rama',
        filters: {'filtro': 'vigente'},
        scrollOffset: 90,
        focus: 'celda-septiembre',
      );
      final session = NavigationSession(initialContext: origin);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [NavigationSessionObserver(session)],
          onGenerateInitialRoutes: (_) => [
            AppRouter.generateRoute(
              const RouteSettings(name: '/desconocida'),
              navigationSession: session,
            ),
          ],
          onGenerateRoute: (settings) =>
              AppRouter.generateRoute(settings, navigationSession: session),
        ),
      );
      await tester.tap(find.text('Volver'));
      await tester.pumpAndSettle();
      expect(session.context, same(origin));
      expect(find.text('Marcador técnico · /real'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Publicación inicial distinta respeta el ciclo de construcción', (
    tester,
  ) async {
    final session = sessionAt(2026, 7);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      NavigationSessionScope(
        session: session,
        child: MaterialApp(
          navigatorObservers: [NavigationSessionObserver(session)],
          onGenerateInitialRoutes: (_) => [
            AppRouter.generateRoute(
              const RouteSettings(name: '/real?a=2024&m=02'),
              navigationSession: session,
            ),
          ],
          onGenerateRoute: (settings) =>
              AppRouter.generateRoute(settings, navigationSession: session),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(session.context.destination, SessionDestination.actual);
    expect(session.period, NavigationPeriod(2024, 2));
    expect(tester.takeException(), isNull);
  });
}
