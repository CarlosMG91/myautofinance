import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

import '../../examples/ui_kit.dart';
import 'kit_test.dart' show host, loadAfFonts;

void main() {
  setUpAll(loadAfFonts);
  final scenarios = <String, (Size, Widget)>{
    'windows': (const Size(1440, 1000), const AfKitExample()),
    'android': (const Size(360, 1100), const AfKitExample()),
    'texto-200': (
      const Size(360, 1650),
      host(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            AfPeriodSelector(
              label: 'Periodo',
              selectedId: 'enero',
              options: const [
                AfPeriodOption(id: 'enero', label: 'Enero de 2026'),
              ],
              onChanged: (_) {},
            ),
            AfSummaryCard(
              label: 'Resultado real del mes',
              amount: const AfAmount(122975),
              contextLabel: 'Enero de 2026 · movimientos',
              tone: AfCardTone.real,
              onDetail: () {},
            ),
            const AfSummaryCard(
              label: 'Foto patrimonial · día 1',
              amount: AfAmount.missing('Falta Cartera'),
              contextLabel: 'Febrero de 2026',
            ),
            const AfComparisonBadge(AfComparisonState.unbudgeted),
            const AfStatus(
              kind: AfStatusKind.divergence,
              message: 'Hay cambios en ambas copias. Conserva la copia local.',
            ),
          ],
        ),
        scale: 2,
        reducedMotion: true,
      ),
    ),
    'graficos': (
      const Size(960, 2450),
      host(
        const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            AfBarChart(
              title: 'Comparación firmada',
              period: 'Enero 2026',
              data: [
                AfBarDatum(
                  label: 'Real',
                  value: AfChartValue.euros(-35025),
                  role: AfSeriesRole.real,
                ),
                AfBarDatum(
                  label: 'Presupuesto',
                  value: AfChartValue.euros(-40000),
                  role: AfSeriesRole.budget,
                ),
                AfBarDatum(
                  label: 'Ingreso real',
                  value: AfChartValue.euros(10000),
                  role: AfSeriesRole.real,
                ),
                AfBarDatum(
                  label: 'Cero registrado',
                  value: AfChartValue.euros(0),
                  role: AfSeriesRole.real,
                ),
                AfBarDatum(
                  label: 'Ocio',
                  value: AfChartValue.unbudgeted(),
                  role: AfSeriesRole.budget,
                ),
              ],
            ),
            AfTimeChart(
              title: 'Foto patrimonial con huecos',
              period: 'Enero–abril 2026',
              series: [
                AfTimeSeries(
                  label: 'Neto',
                  role: AfSeriesRole.asset,
                  points: [
                    AfTimePoint(
                      periodIndex: 0,
                      label: 'Enero',
                      value: AfChartValue.euros(1400000),
                    ),
                    AfTimePoint(
                      periodIndex: 1,
                      label: 'Febrero',
                      value: AfChartValue.missing(
                        AfChartUnit.eur,
                        'Foto incompleta',
                      ),
                    ),
                    AfTimePoint(
                      periodIndex: 3,
                      label: 'Abril',
                      value: AfChartValue.euros(1450000),
                    ),
                  ],
                ),
              ],
            ),
            AfDistributionChart(
              title: 'Distribución de activos',
              period: 'Foto del 1 de enero',
              state: AfDistributionState.complete,
              assets: [
                AfAssetDatum(
                  id: 'cuenta',
                  label: 'Cuenta principal',
                  cents: 600000,
                ),
                AfAssetDatum(
                  id: 'ahorro',
                  label: 'Cuenta de ahorro',
                  cents: 300000,
                ),
                AfAssetDatum(id: 'cartera', label: 'Cartera', cents: 1000000),
              ],
              totalAssets: AfAmount(1900000),
              debt: AfAmount(500000),
            ),
          ],
        ),
      ),
    ),
    'ceros-ausencia': (
      const Size(960, 1700),
      host(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            const AfBarChart(
              title: 'Ceros registrados y ausencia',
              period: 'Febrero 2026',
              data: [
                AfBarDatum(
                  label: 'Real',
                  value: AfChartValue.euros(0),
                  role: AfSeriesRole.real,
                ),
                AfBarDatum(
                  label: 'Presupuesto',
                  value: AfChartValue.unbudgeted(),
                  role: AfSeriesRole.budget,
                ),
              ],
            ),
            AfTimeChart(
              title: 'Colchón constante',
              period: 'Enero–febrero 2026',
              series: [
                AfTimeSeries(
                  label: 'Colchón',
                  role: AfSeriesRole.real,
                  points: [
                    AfTimePoint(
                      periodIndex: 0,
                      label: 'Enero',
                      value: AfChartValue.months(3),
                    ),
                    AfTimePoint(
                      periodIndex: 1,
                      label: 'Febrero',
                      value: AfChartValue.months(3),
                    ),
                  ],
                ),
              ],
            ),
            const AfDistributionChart(
              title: 'Activos cero',
              period: 'Foto del 1 de febrero',
              state: AfDistributionState.complete,
              assets: [
                AfAssetDatum(id: 'cuenta', label: 'Cuenta principal', cents: 0),
              ],
              totalAssets: AfAmount(0),
              debt: AfAmount(500000),
            ),
            const AfDistributionChart(
              title: 'Foto incompleta',
              period: '1 de marzo',
              state: AfDistributionState.missing,
              assets: [],
              totalAssets: AfAmount.missing('Falta Cartera'),
              debt: AfAmount.missing('Falta Cartera'),
              reason: 'Falta Cartera',
            ),
          ],
        ),
      ),
    ),
  };
  for (final entry in scenarios.entries) {
    testWidgets('Golden ${entry.key}', (tester) async {
      tester.view.physicalSize = entry.value.$1;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(key: const ValueKey('capture'), child: entry.value.$2),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('goldens/${entry.key}.png'),
      );
    });
  }
}
