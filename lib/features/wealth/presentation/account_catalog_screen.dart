import 'package:flutter/material.dart';

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
  Future<void> _open(String? id) async {
    await widget.onOpen(id);
    if (mounted) {
      setState(() {
        _data = widget.controller.catalog();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Fichas'),
      automaticallyImplyLeading: false,
    ),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: EdgeInsets.all(constraints.maxWidth < 600 ? 16 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextButton(
                onPressed: widget.onReturn,
                child: Text(widget.returnLabel),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: () => _open(null),
                  child: const Text('Crear ficha'),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Todas las fichas, incluidas las cerradas. Alta y baja son meses incluidos.',
              ),
              FutureBuilder<List<AccountRecord>>(
                future: _data,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return Semantics(
                      liveRegion: true,
                      child: const LinearProgressIndicator(
                        semanticsLabel: 'Leyendo fichas',
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Column(
                      children: [
                        Semantics(
                          liveRegion: true,
                          child: const Text('No se pudieron leer las fichas.'),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            _data = widget.controller.catalog();
                          }),
                          child: const Text('Reintentar'),
                        ),
                      ],
                    );
                  }
                  final items = snapshot.data!;
                  if (items.isEmpty) {
                    return const Text(
                      'Todavía no hay fichas. Crea una cuenta, cartera o deuda.',
                    );
                  }
                  Widget open(AccountRecord item) => TextButton(
                    onPressed: () => _open(item.id),
                    child: Semantics(
                      label:
                          'Abrir ${accountKindLabel(item.kind)} ${item.name}',
                      child: Text(item.name),
                    ),
                  );
                  String period(AccountRecord item) =>
                      '${item.activeFrom.value.substring(0, 7)} → ${item.activeThrough?.value.substring(0, 7) ?? 'Sin baja'}';
                  if (constraints.maxWidth >= 840) {
                    return Table(
                      columnWidths: const {
                        0: FlexColumnWidth(3),
                        1: FlexColumnWidth(2),
                        2: FlexColumnWidth(3),
                      },
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      children: [
                        const TableRow(
                          children: [
                            Padding(
                              padding: EdgeInsets.all(10),
                              child: Text('Nombre'),
                            ),
                            Text('Tipo'),
                            Text('Vigencia inclusiva'),
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
                    children: [
                      for (final item in items)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                open(item),
                                Text('Tipo: ${accountKindLabel(item.kind)}'),
                                Text('Vigencia: ${period(item)}'),
                                if (item.activeThrough != null)
                                  const Text('Cerrada'),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
