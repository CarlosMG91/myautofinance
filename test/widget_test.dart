import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/main.dart';
import 'package:myautofinance/main.dart' as entrypoint;
import 'package:myautofinance/core/config/app_config.dart';

void main() {
  testWidgets('main completa el arranque y abre el índice sin servicios', (
    tester,
  ) async {
    await entrypoint.main();
    await tester.pumpAndSettle();

    expect(find.text('Autofinance · Base técnica'), findsOneWidget);
    expect(find.byType(TextButton), findsNWidgets(5));
    expect(
      tester
          .widget<AutofinanceApp>(find.byType(AutofinanceApp))
          .config
          .environment,
      AppEnvironment.production,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Arranca con la pantalla técnica de Autofinance', (tester) async {
    await tester.pumpWidget(const AutofinanceApp());

    expect(find.text('Autofinance · Base técnica'), findsOneWidget);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      'Autofinance',
    );
    expect(tester.takeException(), isNull);
  });
}
