import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/regional.dart';
import 'package:myautofinance/app/navigation/app_router.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/app/navigation/navigation_session_scope.dart';
import 'package:myautofinance/app/navigation/primary_navigation.dart';
import 'package:myautofinance/app/navigation/session_location.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

import 'support/app_navigation.dart';

void main() {
  test(
    'Capturas independientes aplican periodo nuevo e invalidan posición',
    () async {
      final saved = NavigationContext(
        destination: SessionDestination.actual,
        period: NavigationPeriod(2024, 7),
        branchId: 'rama-sintetica',
        filters: {'abiertas': 'uno,dos'},
        scrollOffset: 125,
        focus: 'celda',
      );
      final session = NavigationSession(initialContext: saved);
      addTearDown(session.dispose);
      await session.changeDestination(SessionDestination.wealth);
      expect(session.context.filters, isEmpty);
      await session.changeDestination(SessionDestination.actual);
      expect(session.context.branchId, saved.branchId);
      expect(session.context.scrollOffset, 125);
      expect(session.context.focus, 'celda');
      await session.changeDestination(SessionDestination.home);
      await session.selectPeriod(NavigationPeriod(2031, 2));
      await session.changeDestination(SessionDestination.actual);
      expect(session.context.period, NavigationPeriod(2031, 2));
      expect(session.context.filters, saved.filters);
      expect(session.context.scrollOffset, 0);
      expect(session.context.focus, isNull);
      expect(session.context.view, PeriodView.annual);
    },
  );

  for (final route in [
    '/inicio?a=2024&m=07',
    '/gestion?a=2024&m=07',
    '/mas?a=2024&m=07',
    '/real/detalle?a=2024&m=07',
    '/presupuesto/detalle?a=2024&m=07',
    '/movimientos/detalle?a=2024&m=07',
  ]) {
    test('Alias local conserva periodo y no reescribe UUID: $route', () {
      final session = NavigationSession();
      addTearDown(session.dispose);
      final parsed =
          SessionLocation.resolve(route, session) as ValidSessionLocation;
      expect(parsed.context.period, NavigationPeriod(2024, 7));
      expect(
        SessionDestination.fromPath('/movimientos/uuid-sintetico'),
        isNull,
      );
    });
  }
  for (final route in [
    '/inicio?a=2024&m=00',
    '/gestion?a=2024&a=2025',
    'https://example.com/inicio',
    '/movimientos/detalle?desde=2026-02-30&hasta=2026-03-01',
  ]) {
    testWidgets('URI inválida no consulta ni cambia contexto: $route', (
      tester,
    ) async {
      final session = NavigationSession();
      addTearDown(session.dispose);
      final original = session.context;
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: (s) =>
              AppRouter.generateRoute(s, navigationSession: session),
          navigatorObservers: [NavigationSessionObserver(session)],
          onGenerateInitialRoutes: (_) => [
            AppRouter.generateRoute(
              RouteSettings(name: route),
              navigationSession: session,
              movements: () async {
                calls++;
                throw StateError('No leer');
              },
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(session.context, same(original));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Guard pendiente, rechazo y error conservan ruta y permiten reintentar',
    (tester) async {
      final session = NavigationSession();
      addTearDown(session.dispose);
      final confirmation = Completer<bool>();
      var calls = 0;
      var fail = false;
      var approved = false;
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [NavigationSessionObserver(session)],
          onGenerateInitialRoutes: (_) => [
            MaterialPageRoute(
              settings: const RouteSettings(name: '/inicio'),
              builder: (_) => Builder(
                builder: (context) => PrimaryNavigation(
                  session: session,
                  title: 'Formulario sintético',
                  periodControl: const Text('Julio de 2024'),
                  beforeNavigate: () {
                    calls++;
                    if (fail) throw StateError('Fallo sintético');
                    if (approved) return Future.value(true);
                    return confirmation.future;
                  },
                  child: const Text('Contenido conservado'),
                ),
              ),
            ),
          ],
          onGenerateRoute: (s) =>
              AppRouter.generateRoute(s, navigationSession: session),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('destination-budget')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('destination-wealth')));
      await tester.pump();
      expect(calls, 1);
      expect(session.context.destination, SessionDestination.home);
      confirmation.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('Contenido conservado'), findsOneWidget);
      fail = true;
      await tester.tap(find.byKey(const ValueKey('destination-budget')));
      await tester.pumpAndSettle();
      expect(session.context.destination, SessionDestination.home);
      expect(find.textContaining('No se pudo resolver'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      fail = false;
      approved = true;
      await tester.tap(find.byKey(const ValueKey('destination-budget')));
      await tester.pumpAndSettle();
      expect(session.context.destination, SessionDestination.budget);
    },
  );

  testWidgets(
    'Fallo del guard de periodo conserva contexto y permite reintentar',
    (tester) async {
      final session = NavigationSession(
        initialContext: NavigationContext(
          destination: SessionDestination.home,
          period: NavigationPeriod(2024, 7),
        ),
      );
      addTearDown(session.dispose);
      var fail = true;
      await tester.pumpWidget(
        MaterialApp(
          locale: AppRegional.locale,
          supportedLocales: AppRegional.supportedLocales,
          localizationsDelegates: AppRegional.delegates,
          home: PrimaryNavigation(
            session: session,
            title: 'Formulario sintético',
            beforeNavigate: () async {
              if (fail) throw StateError('Fallo sintético');
              return true;
            },
            child: const Text('Borrador conservado'),
          ),
        ),
      );
      await tester.tap(find.text('Mes siguiente'));
      await tester.pumpAndSettle();
      expect(session.period, NavigationPeriod(2024, 7));
      expect(find.textContaining('Sigue en este periodo'), findsOneWidget);
      expect(tester.takeException(), isNull);
      fail = false;
      await tester.tap(find.text('Mes siguiente'));
      await tester.pumpAndSettle();
      expect(session.period, NavigationPeriod(2024, 8));
    },
  );

  testWidgets('Más y Real vuelven al origen por Back y Alt+Izquierda', (
    tester,
  ) async {
    final session = NavigationSession(clock: () => DateTime.utc(2026, 1, 9));
    addTearDown(session.dispose);
    await tester.pumpWidget(AutofinanceApp(navigationSession: session));
    await selectAppDestination(tester, SessionDestination.actual);
    expect(session.context.destination, SessionDestination.actual);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(session.context.destination, SessionDestination.more);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(session.context.destination, SessionDestination.home);
    expect(session.period, NavigationPeriod(2026, 1));
  });

  testWidgets('Seleccionar el padre desde captura vuelve al principal', (
    tester,
  ) async {
    final session = NavigationSession(
      initialContext: NavigationContext(
        destination: SessionDestination.budget,
        period: NavigationPeriod(2024, 7),
      ),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [NavigationSessionObserver(session)],
        onGenerateInitialRoutes: (_) => [
          MaterialPageRoute(
            settings: const RouteSettings(name: '/presupuesto/mensual'),
            builder: (_) => PrimaryNavigation(
              session: session,
              title: 'Captura sintética',
              periodControl: const Text('Julio de 2024'),
              beforeNavigate: () async => true,
              child: const Text('Borrador resuelto por el propietario'),
            ),
          ),
        ],
        onGenerateRoute: (settings) =>
            AppRouter.generateRoute(settings, navigationSession: session),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('destination-budget')));
    await tester.pumpAndSettle();
    expect(find.text('Captura sintética'), findsNothing);
    expect(find.text('Marcador técnico · /presupuesto'), findsOneWidget);
    expect(session.period, NavigationPeriod(2024, 7));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Cambiar ancho mantiene estado, foco y scroll; reproyecta selección sin navegar',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = NavigationSession(
        initialContext: NavigationContext(
          destination: SessionDestination.indicators,
          period: NavigationPeriod(2024, 7),
        ),
      );
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AfTheme.light(),
          home: _DraftFixture(session: session),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('synthetic-draft'));
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.enterText(field, 'Borrador conservado');
      await tester.pump();
      final state = tester.state<_DraftFixtureState>(
        find.byType(_DraftFixture),
      );
      final revision = session.revision;
      state.scroll.jumpTo(950);
      await tester.pump();
      final offset = state.scroll.offset;
      expect(offset, greaterThan(0));
      for (final width in [839.0, 840.0, 412.0, 320.0, 1024.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(_DraftFixture)), same(state));
        expect(state.input.text, 'Borrador conservado');
        expect(state.focus.hasFocus, isTrue);
        expect(state.scroll.offset, closeTo(offset, 1));
        final shell = tester.widget<AfShell>(find.byType(AfShell));
        expect(shell.selectedId, width >= 840 ? 'analysis' : 'more');
        expect(session.revision, revision);
        expect(tester.takeException(), isNull);
      }
    },
  );
}

class _DraftFixture extends StatefulWidget {
  const _DraftFixture({required this.session});
  final NavigationSession session;
  @override
  State<_DraftFixture> createState() => _DraftFixtureState();
}

class _DraftFixtureState extends State<_DraftFixture> {
  final input = TextEditingController();
  final focus = FocusNode();
  final scroll = ScrollController();
  @override
  void dispose() {
    input.dispose();
    focus.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PrimaryNavigation(
    session: widget.session,
    title: 'Contenido sintético',
    periodControl: const Text('Julio de 2024'),
    scrollController: scroll,
    child: Column(
      children: [
        const SizedBox(height: 1000),
        TextField(
          key: const Key('synthetic-draft'),
          controller: input,
          focusNode: focus,
        ),
        const SizedBox(height: 1000),
      ],
    ),
  );
}
