import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

/// Comprueba la cifra y etiqueta de la tarjeta sin depender de su reflujo.
Finder wealthSummary(String label, String expected) =>
    find.byWidgetPredicate((widget) {
      if (widget is! AfSummaryCard || widget.label != label) return false;
      final formatted = widget.amount.format(signed: false);
      return formatted.startsWith(expected.replaceAll('\u00a0', ' '));
    });
