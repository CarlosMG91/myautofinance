import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/navigation/app_router.dart';
import 'package:myautofinance/app/navigation/app_routes.dart';
import 'package:myautofinance/core/modules/feature_module.dart';

void main() {
  test('Registra las cinco áreas con rutas únicas y módulos existentes', () {
    expect(
      AppRoutes.destinations.map((entry) => entry.module),
      unorderedEquals([
        ModuleId.monthlyStatus,
        ModuleId.wealth,
        ModuleId.budget,
        ModuleId.actualSpending,
        ModuleId.indicators,
      ]),
    );
    final paths = [
      AppRoutes.home,
      AppRoutes.error,
      ...AppRoutes.destinations.map((entry) => entry.path),
    ];
    expect(paths.toSet(), hasLength(7));
    for (final destination in AppRoutes.destinations) {
      expect(
        AutofinanceApp.modules.map((module) => module.id),
        contains(destination.module),
      );
      final settings = RouteSettings(
        name: destination.path,
        arguments: 'contexto',
      );
      final route = AppRouter.generateRoute(settings);
      expect(route.settings, same(settings));
    }
  });

  for (final destination in AppRoutes.destinations) {
    testWidgets('Abre ${destination.path} desde el arranque y vuelve', (
      tester,
    ) async {
      await tester.pumpWidget(const AutofinanceApp());
      await tester.tap(find.text('${destination.label} · ${destination.path}'));
      await tester.pumpAndSettle();

      expect(find.text(destination.label), findsOneWidget);
      expect(
        find.text('Marcador técnico · ${destination.path}'),
        findsOneWidget,
      );
      expect(
        ModalRoute.of(tester.element(find.text(destination.label)))!
            .settings
            .name,
        destination.path,
      );
      await tester.tap(find.text('Volver'));
      await tester.pumpAndSettle();
      expect(find.text('Autofinance · Base técnica'), findsOneWidget);
      expect(find.byType(TextButton), findsNWidgets(5));
      expect(tester.takeException(), isNull);
    });
  }

  for (final path in [AppRoutes.error, '/no-existe']) {
    testWidgets('Muestra error y permite volver desde $path', (tester) async {
      await tester.pumpWidget(const AutofinanceApp());
      tester.state<NavigatorState>(find.byType(Navigator)).pushNamed(path);
      await tester.pumpAndSettle();
      expect(find.text('Error de navegación'), findsOneWidget);
      expect(find.text('Destino desconocido · $path'), findsOneWidget);
      await tester.tap(find.text('Volver'));
      await tester.pumpAndSettle();
      expect(find.text('Autofinance · Base técnica'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('El retorno del sistema restaura el destino anterior', (
    tester,
  ) async {
    await tester.pumpWidget(const AutofinanceApp());
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushNamed(AppRoutes.wealth);
    await tester.pumpAndSettle();
    navigator.pushNamed('/desconocida');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Marcador técnico · ${AppRoutes.wealth}'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Autofinance · Base técnica'), findsOneWidget);
  });

  testWidgets('El error sin historial ofrece retorno al índice', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        onGenerateInitialRoutes: (_) => [
          AppRouter.generateRoute(const RouteSettings(name: '/desconocida')),
        ],
        onGenerateRoute: AppRouter.generateRoute,
      ),
    );
    expect(find.text('Error de navegación'), findsOneWidget);
    await tester.tap(find.text('Volver'));
    await tester.pumpAndSettle();
    expect(find.text('Autofinance · Base técnica'), findsOneWidget);
  });
}
