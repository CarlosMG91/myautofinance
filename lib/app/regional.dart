import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';

abstract final class AppRegional {
  static const locale = Locale('es', 'ES');
  static const supportedLocales = [locale];
  static const delegates = GlobalMaterialLocalizations.delegates;
  static const currency = 'EUR';

  /// Formato de presentación; no realiza cálculos ni redondeo financiero.
  static String formatEuro(num amount) {
    if (!amount.isFinite) {
      throw ArgumentError('El importe debe ser finito');
    }
    return NumberFormat.currency(
      locale: 'es_ES',
      name: currency,
      symbol: '€',
      decimalDigits: 2,
    ).format(amount);
  }
}
