import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';

/// Recorrido público EP-026; sirve tanto a widgets como a runners nativos.
Future<void> selectAppDestination(
  WidgetTester tester,
  SessionDestination destination,
) async {
  Future<void> tap(Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  if (const {
    SessionDestination.actual,
    SessionDestination.indicators,
    SessionDestination.diagnostics,
  }.contains(destination)) {
    final analysis = find.byKey(const ValueKey('destination-analysis'));
    await tap(
      analysis.evaluate().isNotEmpty
          ? analysis
          : find.byKey(const ValueKey('destination-more')),
    );
    await tap(
      find.text(switch (destination) {
        SessionDestination.actual => 'Real anual',
        SessionDestination.indicators => 'Indicadores',
        _ => 'Diagnóstico de coherencia',
      }).last,
    );
  } else if (destination == SessionDestination.status) {
    await tap(find.byKey(const ValueKey('destination-home')));
    await tap(find.text('Ver detalle'));
  } else if (destination == SessionDestination.management &&
      find.byKey(const ValueKey('destination-management')).evaluate().isEmpty) {
    await tap(find.byKey(const ValueKey('destination-more')));
    await tap(find.text('Gestión').last);
  } else {
    await tap(find.byKey(ValueKey('destination-${destination.name}')));
  }
}
