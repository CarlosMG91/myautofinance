part 'concept_search_key.g.dart';

/// NFD → eliminación de marcas Unicode → case-fold Unicode (15.0.0).
/// Las marcas desaparecen, por lo que su reordenación canónica no afecta
/// al resultado. La tabla compone esas operaciones para cada escalar.
String conceptSearchKey(String text) {
  final result = StringBuffer();
  for (final rune in text.runes) {
    if (rune >= 0xac00 && rune <= 0xd7a3) {
      // Descomposición canónica algorítmica de sílabas Hangul.
      final syllable = rune - 0xac00;
      result.writeCharCode(0x1100 + syllable ~/ 588);
      result.writeCharCode(0x1161 + (syllable % 588) ~/ 28);
      if (syllable % 28 != 0) result.writeCharCode(0x11a7 + syllable % 28);
    } else {
      result.write(_searchMappings[rune] ?? String.fromCharCode(rune));
    }
  }
  return result.toString();
}
