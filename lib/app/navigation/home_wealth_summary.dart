import 'package:flutter/material.dart';

import '../../features/budget/budget.dart' show BudgetMonth;
import '../../features/wealth/wealth.dart';
import '../../ui/autofinance_ui.dart';

/// App compone la lectura patrimonial con Inicio sin dependencia entre módulos.
/// La conexión se resuelve en cada refresco; nunca conserva una base restaurada.
class HomeWealthSummary extends StatefulWidget {
  const HomeWealthSummary({
    super.key,
    required this.load,
    required this.month,
    required this.refreshToken,
    required this.onOpen,
  });
  final WealthManagementLoader? load;
  final BudgetMonth month;
  final Object refreshToken;
  final Future<void> Function(bool photo) onOpen;
  @override
  State<HomeWealthSummary> createState() => _HomeWealthSummaryState();
}

class _HomeWealthSummaryState extends State<HomeWealthSummary> {
  late Future<WealthReading>? _reading;
  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(HomeWealthSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month.value != widget.month.value ||
        oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.load != widget.load) {
      _read();
    }
  }

  void _read() {
    final load = widget.load;
    _reading = load == null
        ? null
        : () async {
            final management = await load();
            return management.readMonth(Month.parse(widget.month.value));
          }();
  }

  @override
  Widget build(BuildContext context) => AfCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        Text('Foto patrimonial', style: Theme.of(context).textTheme.titleLarge),
        Text(
          'Fecha de referencia: ${widget.month.value.substring(8, 10)}/${widget.month.value.substring(5, 7)}/${widget.month.value.substring(0, 4)} · foto manual del día 1',
        ),
        const Text(
          'Valores registrados manualmente, independientes de los movimientos.',
        ),
        if (_reading == null)
          const AfStatus(
            kind: AfStatusKind.missing,
            message: 'Sin dato: servicio patrimonial no disponible.',
          )
        else
          FutureBuilder<WealthReading>(
            future: _reading,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Column(
                  children: [
                    LinearProgressIndicator(
                      semanticsLabel: 'Consultando foto patrimonial',
                    ),
                    AfStatus(
                      kind: AfStatusKind.loading,
                      message: 'Consultando la foto patrimonial…',
                    ),
                  ],
                );
              }
              if (snapshot.hasError) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AfStatus(
                      kind: AfStatusKind.error,
                      message: 'No se pudo consultar la foto patrimonial.',
                    ),
                    AfAction(
                      label: 'Reintentar foto',
                      onPressed: () => setState(_read),
                    ),
                  ],
                );
              }
              final reading = snapshot.data!;
              final totals = reading.totals;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  if (totals == null) ...[
                    AfStatus(
                      kind: AfStatusKind.missing,
                      message: reading.status == WealthSnapshotStatus.absent
                          ? 'Sin dato: falta foto patrimonial.'
                          : 'Sin dato: foto patrimonial incompleta.',
                    ),
                    if (reading.pending.isNotEmpty)
                      Text(
                        'Fichas pendientes: ${reading.pending.map((a) => a.name).join(', ')}',
                      ),
                    const Text(
                      'No se arrastra la foto anterior ni se muestran subtotales parciales.',
                    ),
                  ] else ...[
                    const Text('Patrimonio neto'),
                    AfMoneyText(
                      AfAmount(totals.netWorthCents),
                      signed: false,
                      hero: true,
                    ),
                    AfValueRow(
                      label: 'Activos',
                      value: AfMoneyText(
                        AfAmount(totals.assetsCents),
                        signed: false,
                      ),
                    ),
                    AfValueRow(
                      label: 'Deudas',
                      value: AfMoneyText(
                        AfAmount(totals.debtsCents),
                        signed: false,
                      ),
                    ),
                    AfValueRow(
                      label: 'Activos líquidos',
                      value: AfMoneyText(
                        AfAmount(totals.liquidAssetsCents),
                        signed: false,
                      ),
                    ),
                    const Text('Foto completa · registrada manualmente'),
                    AfAction(
                      label: 'Ver patrimonio',
                      variant: AfActionVariant.link,
                      onPressed: () => widget.onOpen(false),
                    ),
                  ],
                  AfAction(
                    label: totals == null ? 'Registrar foto' : 'Corregir foto',
                    icon: AfIcons.account,
                    onPressed: () => widget.onOpen(true),
                  ),
                ],
              );
            },
          ),
      ],
    ),
  );
}
