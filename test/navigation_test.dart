import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/navigation/app_router.dart';
import 'package:myautofinance/app/navigation/app_routes.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/core/modules/feature_module.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

import 'support/app_navigation.dart';

void main() {
  test(
    'Conserva cinco módulos financieros y rutas históricas con argumentos',
    () {
      expect(
        AppRoutes.destinations.map((e) => e.module),
        unorderedEquals([
          ModuleId.monthlyStatus,
          ModuleId.wealth,
          ModuleId.budget,
          ModuleId.actualSpending,
          ModuleId.indicators,
        ]),
      );
      expect(AppRoutes.destinations.map((e) => e.path).toSet(), hasLength(5));
      for (final destination in AppRoutes.destinations) {
        expect(
          AutofinanceApp.modules.map((m) => m.id),
          contains(destination.module),
        );
        final settings = RouteSettings(
          name: destination.path,
          arguments: 'contexto',
        );
        expect(AppRouter.generateRoute(settings).settings, same(settings));
      }
    },
  );
  for (final destination in [
    SessionDestination.status,
    SessionDestination.wealth,
    SessionDestination.budget,
    SessionDestination.actual,
    SessionDestination.indicators,
  ]) {
    testWidgets('Acceso público a ${destination.path}, periodo y retorno', (
      tester,
    ) async {
      final session = NavigationSession(clock: () => DateTime.utc(2026, 1, 9));
      addTearDown(session.dispose);
      await tester.pumpWidget(AutofinanceApp(navigationSession: session));
      await selectAppDestination(tester, destination);
      expect(session.context.destination, destination);
      expect(session.period, NavigationPeriod(2026, 1));
      expect(find.byType(AfShell), findsOneWidget);
      expect(
        find.text('Marcador técnico · ${destination.path}'),
        findsOneWidget,
      );
      final context = tester.element(find.byType(AfShell));
      expect(Localizations.localeOf(context), const Locale('es', 'ES'));
      expect(MaterialLocalizations.of(context).backButtonTooltip, 'Atrás');
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      if (navigator.canPop()) {
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          session.context.destination,
          destination == SessionDestination.status
              ? SessionDestination.home
              : SessionDestination.more,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
  for (final path in [AppRoutes.error, '/no-existe']) {
    testWidgets('Error mantiene nombre y vuelve a Inicio: $path', (
      tester,
    ) async {
      await tester.pumpWidget(const AutofinanceApp());
      tester.state<NavigatorState>(find.byType(Navigator)).pushNamed(path);
      await tester.pumpAndSettle();
      expect(find.text('Destino desconocido · $path'), findsOneWidget);
      expect(
        ModalRoute.of(tester.element(find.text('Error de navegación')))!
            .settings
            .name,
        path,
      );
      await tester.tap(find.text('Volver'));
      await tester.pumpAndSettle();
      expect(find.text('Ver detalle'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Error sin pila ofrece Inicio', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        onGenerateInitialRoutes: (_) => [
          AppRouter.generateRoute(const RouteSettings(name: '/desconocida')),
        ],
        onGenerateRoute: AppRouter.generateRoute,
      ),
    );
    await tester.tap(find.text('Volver'));
    await tester.pumpAndSettle();
    expect(find.text('Ver detalle'), findsOneWidget);
  });
}
