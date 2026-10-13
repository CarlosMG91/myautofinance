import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../ui/autofinance_ui.dart';
import '../domain/account_repository.dart';
import '../domain/wealth_reading.dart';
import '../domain/wealth_repository.dart';
import 'account_catalog_screen.dart';

String wealthPhotoStatus(WealthSnapshotStatus status) => switch (status) {
  WealthSnapshotStatus.absent => 'Sin dato: falta foto patrimonial',
  WealthSnapshotStatus.incomplete => 'Sin dato: foto patrimonial incompleta',
  WealthSnapshotStatus.complete => 'Foto completa',
};

/// Conserva los doce resultados originales, incluyendo discontinuidades.
class WealthHistory extends StatelessWidget {
  const WealthHistory({
    super.key,
    required this.readings,
    required this.year,
    required this.onSelect,
    required this.onPhoto,
    required this.detail,
  });
  final List<WealthReading> readings;
  final int year;
  final ValueChanged<Month> onSelect;
  final ValueChanged<Month> onPhoto;
  final bool detail;

  String _month(int number) =>
      DateFormat.MMMM('es_ES').format(DateTime(year, number));

  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: const PageStorageKey('wealth-twelve-months'),
    title: Text('Las doce fotos de $year · sin suma anual'),
    children: [
      AfTimeChart(
        title: 'Histórico de activos y deudas',
        period: 'Fotos del día 1 · $year',
        series: [
          for (final role in [AfSeriesRole.asset, AfSeriesRole.debt])
            AfTimeSeries(
              label: role == AfSeriesRole.asset ? 'Activos totales' : 'Deudas',
              role: role,
              points: [
                for (var i = 0; i < readings.length; i++)
                  AfTimePoint(
                    periodIndex: year * 12 + i,
                    label:
                        '${_month(i + 1)}: ${wealthPhotoStatus(readings[i].status)}',
                    value: readings[i].totals == null
                        ? AfChartValue.missing(
                            AfChartUnit.eur,
                            wealthPhotoStatus(readings[i].status)
                                .replaceFirst('Sin dato: ', ''),
                          )
                        : AfChartValue.euros(
                            role == AfSeriesRole.asset
                                ? readings[i].totals!.assetsCents
                                : readings[i].totals!.debtsCents,
                          ),
                    onPressed: () => onSelect(readings[i].month),
                  ),
              ],
            ),
        ],
      ),
      if (detail)
        ExpansionTile(
          key: const PageStorageKey('wealth-history-matrix'),
          title: const Text('Matriz de las doce fotos'),
          // ExpansionTile guarda un bool en PageStorage. Aislar la matriz
          // evita que sus scrolls lean ese estado como un desplazamiento.
          children: [
            PageStorage(bucket: PageStorageBucket(), child: _matrix()),
          ],
        ),
    ],
  );

  Widget _matrix() {
    final accounts = <String, AccountRecord>{};
    for (final reading in readings) {
      for (final account in [
        ...reading.values.map((v) => v.account),
        ...reading.pending,
      ]) {
        accounts[account.id] = account;
      }
    }
    final sorted = accounts.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return AfDetailTable(
      caption: 'Valores por ficha · Liquidez efectiva de cada foto',
      columns: [for (var i = 1; i <= 12; i++) '${_month(i)} · día 1'],
      cellWidth: 280,
      height: 480,
      rows: [
        for (final account in sorted)
          AfDetailRow(
            label: account.name,
            values: [for (final reading in readings) _cell(reading, account)],
          ),
        for (final (label, value) in <(String, int Function(WealthTotals))>[
          ('Activos totales', (t) => t.assetsCents),
          ('Deudas', (t) => t.debtsCents),
          ('Activos líquidos', (t) => t.liquidAssetsCents),
          ('Patrimonio neto', (t) => t.netWorthCents),
        ])
          AfDetailRow(
            label: label,
            total: true,
            values: [
              for (final reading in readings)
                AfMoneyText(
                  reading.totals == null
                      ? const AfAmount.missing(null)
                      : AfAmount(value(reading.totals!)),
                  signed: false,
                  semanticLabel:
                      '$label, foto ${reading.month.value}, ${reading.totals == null ? wealthPhotoStatus(reading.status) : AfAmount(value(reading.totals!)).format(signed: false)}',
                ),
            ],
          ),
      ],
    );
  }

  Widget _cell(WealthReading reading, AccountRecord account) {
    final values = reading.values.where((v) => v.account.id == account.id);
    final pending = reading.pending.where((a) => a.id == account.id);
    if (values.isEmpty && pending.isEmpty) {
      return const Text('Fuera de vigencia', style: TextStyle(fontSize: 14));
    }
    final effective = values.isEmpty ? pending.first : values.first.account;
    final classification = effective.liquidity == null
        ? 'Deuda'
        : liquidityLabel(effective.liquidity!);
    final amount = values.isEmpty
        ? 'Pendiente'
        : AfAmount(values.first.amountCents).format(signed: false);
    return Semantics(
      label:
          '${account.name}, foto ${reading.month.value}, $classification, $amount. Editar foto',
      excludeSemantics: true,
      child: TextButton(
        onPressed: () => onPhoto(reading.month),
        child: Text(
          '$amount · $classification',
          style: const TextStyle(fontSize: 14),
        ),
      ),
    );
  }
}
