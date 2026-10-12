import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

/// Ejecutar: flutter run -t examples/ui_kit.dart --dart-define=APP_ENV=test
/// Dataset sintético de EP-001. No abre base de datos ni servicios de red.
void main() => runApp(const AfKitExample());

class AfKitExample extends StatelessWidget {
  const AfKitExample({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('es', 'ES'),
    supportedLocales: const [Locale('es', 'ES')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: AfTheme.light(),
    highContrastTheme: AfTheme.light(highContrast: true),
    themeMode: ThemeMode.light,
    home: const AfKitGallery(),
  );
}

class AfKitGallery extends StatefulWidget {
  const AfKitGallery({super.key});
  @override
  State<AfKitGallery> createState() => _AfKitGalleryState();
}

class _AfKitGalleryState extends State<AfKitGallery> {
  final _amount = TextEditingController();
  final _form = GlobalKey<FormState>();
  String _period = '2026-01';
  String _selected = 'inicio';
  bool _expanded = false;
  String? _message;
  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _detail() =>
      setState(() => _message = 'Detalle sintético seleccionado.');
  @override
  Widget build(BuildContext context) => AfShell(
    primaryItems: const [
      AfNavItem(id: 'inicio', label: 'Inicio', icon: AfIcons.home),
      AfNavItem(
        id: 'presupuesto',
        label: 'Presupuesto',
        icon: AfIcons.calendar,
      ),
      AfNavItem(id: 'movimientos', label: 'Movimientos', icon: AfIcons.receipt),
      AfNavItem(id: 'patrimonio', label: 'Patrimonio', icon: AfIcons.account),
      AfNavItem(id: 'analisis', label: 'Análisis', icon: AfIcons.analysis),
    ],
    utilityItems: const [
      AfNavItem(id: 'gestion', label: 'Gestión', icon: AfIcons.management),
    ],
    selectedId: _selected,
    onSelect: (id) async {
      setState(() => _selected = id);
      return true;
    },
    periodControl: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: AfPeriodSelector(
        label: 'Periodo de demostración',
        selectedId: _period,
        options: const [
          AfPeriodOption(id: '2026-01', label: 'Enero de 2026'),
          AfPeriodOption(id: '2026-02', label: 'Febrero de 2026'),
        ],
        onChanged: (value) => setState(() {
          _period = value;
          _message =
              'Periodo seleccionado: $value. Las cifras siguientes son fixtures fijos de enero.';
        }),
      ),
    ),
    page: AfPageSlots(
      title: 'Tu mes, en perspectiva',
      contextTrail: const Text(
        'Demostración del kit · cifras sintéticas de enero de 2026 · EUR',
      ),
      actions: [
        AfAction(
          label: 'Importar CSV',
          icon: AfIcons.importFile,
          onPressed: _detail,
        ),
      ],
      status: _message == null
          ? null
          : AfStatus(kind: AfStatusKind.success, message: _message!),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 24,
        children: [
          AfResponsiveGrid(
            children: [
              AfSummaryCard(
                label: 'Resultado real del mes',
                amount: const AfAmount(122975),
                contextLabel: 'Suma firmada de movimientos · enero 2026',
                tone: AfCardTone.real,
                onDetail: _detail,
              ),
              AfSummaryCard(
                label: 'Resultado presupuestado',
                amount: const AfAmount(110000),
                contextLabel: 'Partidas del mes · enero 2026',
                tone: AfCardTone.budget,
                onDetail: _detail,
              ),
              AfSummaryCard(
                label: 'Diferencia real − presupuesto',
                amount: const AfAmount(12975),
                contextLabel: 'Comparación algebraica · enero 2026',
                comparison: AfComparisonState.favorable,
                onDetail: _detail,
              ),
            ],
          ),
          AfResponsiveGrid(
            columns: 2,
            minimumWidth: 400,
            children: [
              AfBarChart(
                title: 'Real y presupuesto',
                period: 'Enero de 2026',
                data: [
                  AfBarDatum(
                    label: 'Real',
                    value: const AfChartValue.euros(122975),
                    role: AfSeriesRole.real,
                    onPressed: _detail,
                  ),
                  AfBarDatum(
                    label: 'Presupuesto',
                    value: const AfChartValue.euros(110000),
                    role: AfSeriesRole.budget,
                    onPressed: _detail,
                  ),
                ],
              ),
              AfSummaryCard(
                label: 'Foto patrimonial · día 1',
                amount: const AfAmount(1400000),
                signed: false,
                contextLabel: 'Patrimonio neto · 1 de enero de 2026',
                onDetail: _detail,
              ),
            ],
          ),
          const AfBarChart(
            title: 'Alimentación · signos y ausencia',
            period: 'Fixtures de enero',
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
                label: 'Cero registrado',
                value: AfChartValue.euros(0),
                role: AfSeriesRole.real,
              ),
              AfBarDatum(
                label: 'Ocio',
                value: AfChartValue.missing(AfChartUnit.eur, 'Sin presupuesto'),
                role: AfSeriesRole.budget,
              ),
            ],
          ),
          const AfTimeChart(
            title: 'Patrimonio neto',
            period: 'Enero–abril de 2026 · fotos del día 1',
            series: [
              AfTimeSeries(
                label: 'Patrimonio neto',
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
                    periodIndex: 2,
                    label: 'Marzo',
                    value: AfChartValue.missing(
                      AfChartUnit.eur,
                      'Foto ausente',
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
          const AfDistributionChart(
            title: 'Distribución de activos',
            period: '1 de enero de 2026',
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
          AfCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                Text(
                  'Filas y estados',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                AfValueRow(
                  label: 'Compra semanal',
                  icon: AfIcons.receipt,
                  contextLabel: 'Cuenta principal · 15/01/2026 · Alimentación / Supermercado',
                  value: const AfMoneyText(AfAmount(-35025)),
                  onPressed: _detail,
                ),
                const AfValueRow(
                  label: 'Cuenta de ahorro',
                  icon: AfIcons.account,
                  contextLabel: 'Foto manual · 1 de febrero · registrada',
                  value: AfMoneyText(AfAmount(0), signed: false),
                ),
                const AfComparisonBadge(AfComparisonState.unbudgeted),
              ],
            ),
          ),
          AfDetailTable(
            caption: 'Ver detalle · Alimentación · 2026 · EUR',
            columns: const ['Enero', 'Febrero', 'Total entregado'],
            rows: [
              AfDetailRow(
                label: 'Alimentación',
                onExpand: () => setState(() => _expanded = !_expanded),
                expanded: _expanded,
                values: const [
                  AfMoneyText(AfAmount(-35025)),
                  AfMoneyText(AfAmount(-42010)),
                  AfMoneyText(AfAmount(-77035)),
                ],
              ),
              if (_expanded)
                const AfDetailRow(
                  label: 'Supermercado / Compra semanal',
                  depth: 1,
                  values: [
                    AfMoneyText(AfAmount(-35025)),
                    AfMoneyText(AfAmount(-42010)),
                    AfMoneyText(AfAmount(-77035)),
                  ],
                ),
            ],
          ),
          AfCard(
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 16,
                children: [
                  Text(
                    'Formulario sintético',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  AfFormField(
                    label: 'Importe EUR',
                    controller: _amount,
                    required: true,
                    help: 'Ejemplo de error y borrador. No se guarda.',
                    validator: (value) => value == null || value.isEmpty
                        ? 'Escribe un importe para revisar el ejemplo.'
                        : null,
                  ),
                  AfAction(
                    label: 'Revisar',
                    icon: AfIcons.confirm,
                    variant: AfActionVariant.primary,
                    onPressed: () {
                      _form.currentState!.validate();
                    },
                  ),
                  const AfAction(
                    label: 'Guardar',
                    onPressed: null,
                    unavailableReason: 'Ejemplo sin persistencia.',
                  ),
                ],
              ),
            ),
          ),
          for (final kind in AfStatusKind.values)
            AfStatus(
              kind: kind,
              message:
                  'Estado sintético: ${kind.name}. Conserva el contexto de origen.',
            ),
        ],
      ),
    ),
  );
}
