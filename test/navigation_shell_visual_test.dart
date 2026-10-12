import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';

import 'ui/kit_test.dart' show loadAfFonts;

void main() {
  setUpAll(() async {
    await loadAfFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final scenario in <String, ({Size size, double scale})>{
    'windows': (size: const Size(1440, 900), scale: 1),
    'android': (size: const Size(412, 915), scale: 1),
    'texto-200': (size: const Size(320, 1100), scale: 2),
  }.entries) {
    testWidgets(
      'Shell de agrupación ${scenario.key} sin servicios ni cifras ficticias',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = scenario.value.size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final session = NavigationSession(
          initialContext: NavigationContext(
            destination: SessionDestination.more,
            period: NavigationPeriod(2026, 1),
          ),
        );
        addTearDown(session.dispose);
        tester.platformDispatcher.textScaleFactorTestValue =
            scenario.value.scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('shell-visual'),
            child: AutofinanceApp(navigationSession: session),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Real anual'), findsOneWidget);
        expect(find.text('Indicadores'), findsOneWidget);
        await expectLater(
          find.byKey(const Key('shell-visual')),
          matchesGoldenFile('shell_goldens/${scenario.key}.png'),
        );
        if (scenario.value.scale == 2) {
          await tester.ensureVisible(find.text('Diagnóstico de coherencia'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(const Key('shell-visual')),
            matchesGoldenFile('shell_goldens/texto-200-contenido.png'),
          );
        }
      },
    );
  }
}
