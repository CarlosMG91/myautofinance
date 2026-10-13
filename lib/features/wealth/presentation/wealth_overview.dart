import 'package:flutter/material.dart';

import '../../../ui/autofinance_ui.dart';
import '../domain/wealth_reading.dart';

/// Presentación de una lectura calculada por patrimonio; no consulta ni escribe.
class WealthOverview extends StatelessWidget {
  const WealthOverview({
    super.key,
    required this.reading,
    required this.period,
  });
  final WealthReading reading;
  final String period;

  AfAmount _amount(int? value) =>
      value == null ? const AfAmount.missing(null) : AfAmount(value);

  @override
  Widget build(BuildContext context) {
    final totals = reading.totals;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 24,
      children: [
        AfSummaryCard(
          label: 'Patrimonio neto',
          amount: _amount(totals?.netWorthCents),
          signed: false,
          tone: AfCardTone.real,
          contextLabel: 'Activos menos deudas · Foto del día 1 · $period',
        ),
        AfResponsiveGrid(
          children: [
            AfSummaryCard(
              label: 'Activos totales',
              amount: _amount(totals?.assetsCents),
              signed: false,
              contextLabel: 'Cuentas y carteras · $period',
            ),
            AfSummaryCard(
              label: 'Deudas',
              amount: _amount(totals?.debtsCents),
              signed: false,
              contextLabel: 'Pasivos de la foto · Se restan de los activos',
            ),
            AfSummaryCard(
              label: 'Activos líquidos',
              amount: _amount(totals?.liquidAssetsCents),
              signed: false,
              contextLabel:
                  'Liquidez vigente en $period · Sin descontar deudas',
            ),
          ],
        ),
        AfDistributionChart(
          title: 'Distribución de activos por liquidez',
          period: period,
          state: totals == null
              ? AfDistributionState.missing
              : AfDistributionState.complete,
          reason: 'Sin dato: la distribución requiere una foto completa.',
          assets: totals == null
              ? const []
              : [
                  AfAssetDatum(
                    id: 'liquid',
                    label: 'Líquida',
                    cents: totals.liquidAssetsCents,
                  ),
                  AfAssetDatum(
                    id: 'medium',
                    label: 'Media',
                    cents: totals.mediumAssetsCents,
                  ),
                  AfAssetDatum(
                    id: 'illiquid',
                    label: 'No líquida',
                    cents: totals.illiquidAssetsCents,
                  ),
                ],
          totalAssets: _amount(totals?.assetsCents),
          debt: _amount(totals?.debtsCents),
        ),
      ],
    );
  }
}
