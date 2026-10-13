import 'package:flutter/material.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

import '../domain/account_repository.dart';
import 'wealth_controller.dart';

String accountKindLabel(AccountKind kind) => switch (kind) {
  AccountKind.account => 'Cuenta corriente',
  AccountKind.portfolio => 'Cartera agregada',
  AccountKind.debt => 'Deuda',
};
String liquidityLabel(Liquidity liquidity) => switch (liquidity) {
  Liquidity.liquid => 'Líquida',
  Liquidity.medium => 'Media',
  Liquidity.illiquid => 'No líquida',
};

class AccountCatalogScreen extends StatefulWidget {
  const AccountCatalogScreen({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onReturn,
    this.returnLabel = 'Volver al origen',
  });
  final WealthController controller;
  final Future<void> Function(String? id) onOpen;
  final VoidCallback onReturn;
  final String returnLabel;
  @override
  State<AccountCatalogScreen> createState() => _AccountCatalogScreenState();
}

class _AccountCatalogScreenState extends State<AccountCatalogScreen> {
  late Future<List<AccountRecord>> _data = widget.controller.catalog();
  final _scroll = ScrollController();
  final _createFocus = FocusNode();
  final _focus = <String, FocusNode>{};
  bool _opening = false;
  String? _openError;

  @override
  void dispose() {
    _scroll.dispose();
    _createFocus.dispose();
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _open(String? id) async {
    if (_opening) return;
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    setState(() {
      _opening = true;
      _openError = null;
    });
    try {
      await widget.onOpen(id);
      if (!mounted) return;
      final data = widget.controller.catalog();
      setState(() => _data = data);
      await data;
    } catch (_) {
      if (mounted) {
        setState(
          () => _openError =
              'No se pudo abrir o actualizar la ficha. Inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_scroll.hasClients) {
            _scroll.jumpTo(offset.clamp(0.0, _scroll.position.maxScrollExtent));
          }
          (id == null ? _createFocus : _focus[id])?.requestFocus();
        });
        WidgetsBinding.instance.scheduleFrame();
      }
    }
  }

  @override
  Widget build(BuildContext context) => AfCatalogPage(
    title: 'Fichas',
    scrollController: _scroll,
    contextTrail: const Text('Gestión · Cuentas, carteras y deudas'),
    actions: [
      AfAction(
        label: widget.returnLabel,
        icon: AfIcons.back,
        variant: AfActionVariant.link,
        onPressed: widget.onReturn,
      ),
      FilledButton(
        focusNode: _createFocus,
        onPressed: _opening ? null : () => _open(null),
        child: const Text('Crear ficha'),
      ),
    ],
    child: LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_openError != null)
            AfStatus(kind: AfStatusKind.error, message: _openError!),
          const Text(
            'Todas las fichas, incluidas las cerradas. Alta y baja son meses incluidos.',
          ),
          FutureBuilder<List<AccountRecord>>(
            future: _data,
            builder: (context, snapshot) {
              // Conservar las filas mientras se relee mantiene sus FocusNode
              // adjuntos y la posición del catálogo al volver del editor.
              if (snapshot.connectionState != ConnectionState.done &&
                  !snapshot.hasData) {
                return const AfStatus(
                  kind: AfStatusKind.loading,
                  message: 'Leyendo fichas…',
                );
              }
              if (snapshot.hasError) {
                return AfStatus(
                  kind: AfStatusKind.error,
                  message: 'No se pudieron leer las fichas.',
                  action: AfAction(
                    label: 'Reintentar',
                    onPressed: () => setState(() {
                      _data = widget.controller.catalog();
                    }),
                  ),
                );
              }
              final items = snapshot.data!;
              if (items.isEmpty) {
                return const AfStatus(
                  kind: AfStatusKind.empty,
                  message: 'Todavía no hay fichas. Crea una cuenta, cartera o deuda.',
                );
              }
              Widget open(AccountRecord item) => TextButton(
                focusNode: _focus.putIfAbsent(item.id, FocusNode.new),
                onPressed: _opening ? null : () => _open(item.id),
                child: Semantics(
                  label: 'Abrir ${accountKindLabel(item.kind)} ${item.name}',
                  child: Text(item.name),
                ),
              );
              String period(AccountRecord item) =>
                  '${item.activeFrom.value.substring(0, 7)} → ${item.activeThrough?.value.substring(0, 7) ?? 'Sin baja'}';
              if (constraints.maxWidth >= 840 &&
                  !AfTokens.reflow(context, constraints.maxWidth)) {
                return Table(
                  border: const TableBorder(
                    horizontalInside: BorderSide(color: AfTokens.border),
                  ),
                  columnWidths: const {
                    0: FlexColumnWidth(3),
                    1: FlexColumnWidth(2),
                    2: FlexColumnWidth(3),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    const TableRow(
                      decoration: BoxDecoration(color: AfTokens.surfaceSubtle),
                      children: [
                        Padding(
                          padding: EdgeInsets.all(10),
                          child: Text('Nombre'),
                        ),
                        Padding(
                          padding: EdgeInsets.all(10),
                          child: Text('Tipo'),
                        ),
                        Padding(
                          padding: EdgeInsets.all(10),
                          child: Text('Vigencia inclusiva'),
                        ),
                      ],
                    ),
                    for (final item in items)
                      TableRow(
                        children: [
                          open(item),
                          Text(accountKindLabel(item.kind)),
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Text(
                              '${period(item)}${item.activeThrough != null ? ' · Cerrada' : ''}',
                            ),
                          ),
                        ],
                      ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  for (final item in items)
                    AfCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 12,
                        children: [
                          open(item),
                          Text('Tipo: ${accountKindLabel(item.kind)}'),
                          Text('Vigencia: ${period(item)}'),
                          if (item.activeThrough != null) const Text('Cerrada'),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}
