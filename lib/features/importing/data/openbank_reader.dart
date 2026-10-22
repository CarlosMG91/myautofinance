import 'dart:convert';

import 'package:xml/xml.dart';

import '../domain/interpreted_import.dart';
import '../domain/openbank.dart';

/// Lee únicamente el exportador XHTML estricto observado. No abre enlaces,
/// ejecuta contenido, consulta catálogos ni calcula fotos patrimoniales.
final class OpenbankReader {
  const OpenbankReader();

  OpenbankReadResult read(List<int> bytes) {
    OpenbankReadResult invalid(String reason) => OpenbankReadResult(
      issues: [ImportIssue(code: ImportIssueCode.invalidFile, reason: reason)],
    );
    if (bytes.isEmpty || bytes.length > 16 * 1024 * 1024) {
      return invalid('Extracto vacío o superior a 16 MiB.');
    }
    final text = latin1.decode(bytes);
    if (!text.trimLeft().startsWith(
          '<!DOCTYPE html PUBLIC '
          '"-//W3C//DTD XHTML 1.0 Strict//EN"',
        ) ||
        text.contains('<!ENTITY') ||
        text.contains('<![')) {
      return invalid(
        'Formato no reconocido. Se admite el XLS de Openbank que contiene '
        'XHTML ISO-8859-1; XLS binario y XLSX no están caracterizados.',
      );
    }
    final XmlDocument document;
    try {
      document = XmlDocument.parse(text);
    } on XmlException {
      return invalid(
        'El XHTML está incompleto o dañado. Cero filas aceptadas.',
      );
    }
    final root = document.rootElement;
    final all = root.descendants.whereType<XmlElement>().toList();
    final body = all.where((e) => e.name.local == 'body').toList();
    final meta = all.where((e) => e.name.local == 'meta').toList();
    final tables = all.where((e) => e.name.local == 'table').toList();
    if (root.name.local != 'html' ||
        root.getAttribute('xmlns') != 'http://www.w3.org/1999/xhtml' ||
        meta.length != 1 ||
        meta.single.getAttribute('content')?.toLowerCase() !=
            'text/html; charset=iso-8859-1' ||
        tables.length != 1 ||
        body.length != 1 ||
        root.childElements.map((e) => e.name.local).join('|') != 'head|body' ||
        body.single.childElements.length != 1 ||
        body.single.childElements.single != tables.single ||
        all.any(
          (e) => !const {
            'head',
            'style',
            'meta',
            'body',
            'table',
            'tr',
            'td',
            'b',
            'font',
          }.contains(e.name.local.toLowerCase()),
        )) {
      return invalid('La estructura no corresponde al extracto caracterizado.');
    }
    final trs = tables.single.childElements.toList();
    if (trs.length < 13 ||
        trs.any((e) => e.name.local != 'tr') ||
        all.where((e) => e.name.local == 'tr').length != trs.length) {
      return invalid('Tabla de movimientos incompleta o no reconocida.');
    }
    final rows = <List<String>>[];
    for (var i = 0; i < trs.length; i++) {
      final children = trs[i].childElements.toList();
      // El exportador envuelve tres TD en FONT en las filas 6–8. Es una
      // peculiaridad observada; no reparar estructuras HTML arbitrarias.
      final wrapped =
          i >= 5 &&
          i <= 7 &&
          children.length == 8 &&
          children[1].name.local == 'font' &&
          children[1].childElements.length == 3;
      final cells = [
        for (var j = 0; j < children.length; j++)
          if (wrapped && j == 1) ...children[j].childElements else children[j],
      ];
      if (cells.length != 10 ||
          cells.any(
            (e) =>
                e.name.local != 'td' ||
                e.getAttribute('colspan') != null ||
                e.getAttribute('rowspan') != null,
          )) {
        return invalid(
          'Tabla 1 · fila física ${i + 1}: se esperan diez celdas.',
        );
      }
      rows.add(cells.map((e) => e.innerText).toList());
    }
    String cell(int row, int column) => rows[row - 1][column - 1].trim();
    bool blank(int row) => rows[row - 1].every((c) => c.trim().isEmpty);
    final header = [
      for (final col in [2, 4, 6, 8, 10]) cell(11, col),
    ];
    if (!blank(1) ||
        cell(2, 2).replaceAll(RegExp(r'\s+'), ' ') != 'Cuentas - Movimientos' ||
        !cell(3, 10).startsWith('Fecha de descarga:') ||
        cell(4, 2) != 'Número de Cuenta:' ||
        !RegExp(r'^\d{4} \d{4} \d{2} \d{10}$').hasMatch(cell(4, 4)) ||
        !blank(5) ||
        cell(6, 2) != 'Descripción:' ||
        cell(6, 4).isEmpty ||
        cell(7, 2) != 'Titular:' ||
        cell(7, 4).isEmpty ||
        cell(8, 2) != 'Saldo:' ||
        !cell(8, 4).endsWith(' EUR') ||
        _cents(cell(8, 4).replaceFirst(RegExp(r' EUR$'), '')) == null ||
        cell(9, 2) != 'Lista de Movimientos' ||
        !blank(10) ||
        header.join('|') !=
            'Fecha Operación|Fecha Valor|Concepto|Importe|Saldo' ||
        !blank(rows.length)) {
      return invalid('Cabeceras, identidad de cuenta o pie no reconocidos.');
    }
    // No ignorar contenido añadido en las celdas informativas o separadoras.
    const occupied = <int, Set<int>>{
      2: {2},
      3: {10},
      4: {2, 4},
      6: {2, 4},
      7: {2, 4},
      8: {2, 4},
      9: {2},
      11: {2, 4, 6, 8, 10},
    };
    for (var r = 1; r <= 11; r++) {
      for (var col = 1; col <= 10; col++) {
        if (!(occupied[r]?.contains(col) ?? false) && cell(r, col).isNotEmpty) {
          return invalid(
            'Tabla 1 · fila física $r: contenido informativo desconocido.',
          );
        }
      }
    }
    final records = <OpenbankRecord>[];
    final issues = <ImportIssue>[];
    for (var i = 11; i < rows.length - 1; i++) {
      final row = rows[i];
      final physical = i + 1;
      void issue(String field, String reason) => issues.add(
        ImportIssue(
          code: ImportIssueCode.invalidField,
          sourceOrdinal: physical,
          field: field,
          reason: 'Tabla 1 · fila física $physical · $reason',
        ),
      );
      final before = issues.length;
      if ([0, 2, 4, 6, 8].any((c) => row[c].trim().isNotEmpty)) {
        issue('estructura', 'Separador con contenido no reconocido.');
      }
      final operation = _date(row[1].trim());
      final value = _date(row[3].trim());
      if (operation == null) {
        issue('Fecha Operación', 'Fecha DD/MM/AAAA inválida.');
      }
      if (value == null) issue('Fecha Valor', 'Fecha DD/MM/AAAA inválida.');
      final amount = _cents(row[7].trim());
      if (amount == null || amount == 0) {
        issue(
          'Importe',
          'Importe firmado distinto de cero, con coma y dos decimales, en céntimos int64.',
        );
      }
      if (_cents(row[9].trim()) == null) {
        issue('Saldo', 'Saldo informativo inválido.');
      }
      if (row[5].trim().isEmpty) {
        issue('Concepto', 'El concepto es obligatorio.');
      }
      if (issues.length != before) continue;
      records.add(
        OpenbankRecord(
          physicalRow: physical,
          valueDate: value!,
          concept: row[5].trim(),
          amountCents: amount!,
          originalFields: [
            const ImportOriginalField('unidad', 'Tabla 1'),
            ImportOriginalField('fila_física', '$physical'),
            ImportOriginalField('Número de Cuenta', rows[3][3]),
            ImportOriginalField('Descripción', rows[5][3]),
            for (var col = 0; col < 5; col++)
              ImportOriginalField(header[col], row[col * 2 + 1]),
          ],
        ),
      );
    }
    return OpenbankReadResult(records: records, issues: issues);
  }

  String? _date(String text) {
    if (!RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(text)) return null;
    final p = text.split('/').map(int.parse).toList();
    if (p[2] == 0) return null;
    final d = DateTime.utc(p[2], p[1], p[0]);
    if (d.year != p[2] || d.month != p[1] || d.day != p[0]) return null;
    return '${p[2].toString().padLeft(4, '0')}-${p[1].toString().padLeft(2, '0')}-${p[0].toString().padLeft(2, '0')}';
  }

  int? _cents(String text) {
    if (!RegExp(r'^-?(?:\d+|\d{1,3}(?:\.\d{3})+),\d{2}$').hasMatch(text)) {
      return null;
    }
    final value = BigInt.parse(text.replaceAll('.', '').replaceAll(',', ''));
    if (value < BigInt.parse('-9223372036854775808') ||
        value > BigInt.parse('9223372036854775807')) {
      return null;
    }
    return value.toInt();
  }
}
