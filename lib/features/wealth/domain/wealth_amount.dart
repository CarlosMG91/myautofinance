import 'wealth_repository.dart';

/// EUR manuales, sin pasar por double ni redondear fracciones de céntimo.
int? parseWealthAmount(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  final match = RegExp(r'^([0-9]+)(?:[,.]([0-9]{1,2}))?$').firstMatch(text);
  if (match == null) {
    throw const WealthFailure('Introduce un valor de 0,00 € o más');
  }
  final cents =
      BigInt.parse(match.group(1)!) * BigInt.from(100) +
      BigInt.parse((match.group(2) ?? '').padRight(2, '0'));
  if (cents > BigInt.parse('9223372036854775807')) {
    throw const WealthFailure('El valor supera el máximo admitido.');
  }
  return cents.toInt();
}

String wealthAmountText(int cents) =>
    '${cents ~/ 100},${(cents % 100).toString().padLeft(2, '0')}';
