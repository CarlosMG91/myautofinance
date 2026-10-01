import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/main.dart';

void main() {
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
