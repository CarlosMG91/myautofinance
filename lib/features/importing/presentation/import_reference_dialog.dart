import 'package:flutter/material.dart';

import '../importing.dart';
import '../../wealth/wealth.dart';
import 'import_widgets.dart';

/// Devuelve una decisión en memoria. Cerrar el diálogo nunca crea referencias.
Future<Object?> chooseImportReference(
  BuildContext context,
  ImportReference ref,
  ImportPreviewSnapshot data,
  ImportReferenceBindings bindings,
) => showDialog<Object>(
  context: context,
  builder: (_) =>
      _ReferenceDialog(reference: ref, data: data, bindings: bindings),
);

class _ReferenceDialog extends StatefulWidget {
  const _ReferenceDialog({
    required this.reference,
    required this.data,
    required this.bindings,
  });
  final ImportReference reference;
  final ImportPreviewSnapshot data;
  final ImportReferenceBindings bindings;
  @override
  State<_ReferenceDialog> createState() => _ReferenceDialogState();
}

class _ReferenceDialogState extends State<_ReferenceDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _from = TextEditingController(text: '2026-01');
  final _through = TextEditingController();
  String? _existing, _parent;
  bool _create = false;
  bool? _income;
  Liquidity _liquidity = Liquidity.liquid;
  bool get account => widget.reference is PendingImportAccount;
  @override
  void initState() {
    super.initState();
    _name.text = switch (widget.reference) {
      PendingImportAccount(:final account) => account.name ?? '',
      PendingImportCategory(:final category) => category.path.last,
    };
  }

  @override
  void dispose() {
    _name.dispose();
    _from.dispose();
    _through.dispose();
    super.dispose();
  }

  Month? _month(String text) {
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(text)) return null;
    try {
      return Month(
        int.parse(text.substring(0, 4)),
        int.parse(text.substring(5, 7)),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final parents = <String, ImportCategoryTarget>{
      for (final node in widget.data.categories.where(
        (n) => !n.archived && n.depth < 3,
      ))
        'id:${node.id}': ImportCategoryTarget.existing(node.id),
      for (final ref in widget.bindings.newCategories.keys)
        if (widget.reference is! PendingImportCategory ||
            ref != (widget.reference as PendingImportCategory).category)
          'plan:${ref.path.join('/')}': ImportCategoryTarget.proposed(ref),
    };
    return AlertDialog(
      title: Text(account ? 'Resolver cuenta' : 'Resolver categoría'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'La decisión se aplica a todas las filas de esta referencia. Las altas se guardan junto al lote.',
                ),
                SwitchListTile(
                  title: const Text('Preparar nueva referencia'),
                  value: _create,
                  onChanged: (v) => setState(() => _create = v),
                ),
                if (!_create)
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Identidad existente',
                    ),
                    items: account
                        ? [
                            for (final a in widget.data.accounts.where(
                              (a) => a.kind == AccountKind.account,
                            ))
                              DropdownMenuItem(
                                value: a.id,
                                child: Text('${a.name} · ${a.id}'),
                              ),
                          ]
                        : [
                            for (final n in widget.data.categories.where(
                              (n) => !n.archived,
                            ))
                              DropdownMenuItem(
                                value: n.id,
                                child: Text(
                                  '${importCategoryPath(n.id, widget.data.categories)} · ${n.id}',
                                ),
                              ),
                          ],
                    onChanged: (v) => _existing = v,
                    validator: (_) =>
                        _existing == null ? 'Elige una identidad.' : null,
                  ),
                if (_create) ...[
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                    validator: (v) => (v?.trim().isEmpty ?? true)
                        ? 'Escribe un nombre.'
                        : null,
                  ),
                  if (account) ...[
                    TextFormField(
                      controller: _from,
                      decoration: const InputDecoration(
                        labelText: 'Vigente desde (AAAA-MM)',
                      ),
                      validator: (v) =>
                          _month(v ?? '') == null ? 'Mes inválido.' : null,
                    ),
                    TextFormField(
                      controller: _through,
                      decoration: const InputDecoration(
                        labelText: 'Vigente hasta (AAAA-MM, opcional)',
                      ),
                      validator: (v) => (v ?? '').isEmpty
                          ? null
                          : _month(v!) == null
                          ? 'Mes inválido.'
                          : _month(_from.text) != null &&
                                _month(v)!.compareTo(_month(_from.text)!) < 0
                          ? 'El fin es anterior al inicio.'
                          : null,
                    ),
                    DropdownButtonFormField<Liquidity>(
                      initialValue: _liquidity,
                      decoration: const InputDecoration(labelText: 'Liquidez'),
                      items: [
                        for (final l in Liquidity.values)
                          DropdownMenuItem(
                            value: l,
                            child: Text(switch (l) {
                              Liquidity.liquid => 'Líquida',
                              Liquidity.medium => 'Media',
                              Liquidity.illiquid => 'No líquida',
                            }),
                          ),
                      ],
                      onChanged: (v) => _liquidity = v!,
                    ),
                  ] else ...[
                    DropdownButtonFormField<String>(
                      initialValue: 'root',
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Padre'),
                      items: [
                        const DropdownMenuItem(
                          value: 'root',
                          child: Text('Sin padre · nueva raíz'),
                        ),
                        for (final e in parents.entries)
                          DropdownMenuItem(
                            value: e.key,
                            child: Text(
                              e.value.existingId != null
                                  ? importCategoryPath(
                                      e.value.existingId!,
                                      widget.data.categories,
                                    )
                                  : '${e.value.proposedReference!.path.join(' / ')} · preparada',
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        _parent = v == 'root' ? null : v;
                        _income = null;
                      }),
                    ),
                    if (_parent == null)
                      DropdownButtonFormField<bool>(
                        decoration: const InputDecoration(
                          labelText: '¿Es raíz de ingreso?',
                        ),
                        items: const [
                          DropdownMenuItem(value: true, child: Text('Ingreso')),
                          DropdownMenuItem(
                            value: false,
                            child: Text('No ingreso'),
                          ),
                        ],
                        onChanged: (v) => _income = v,
                        validator: (_) => _income == null
                            ? 'Elige la marca de ingreso.'
                            : null,
                      ),
                    if (_parent != null)
                      const Text(
                        'El hijo hereda la marca de ingreso. Máximo tres niveles; el núcleo valida el plan.',
                      ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(
              context,
              !_create
                  ? _existing
                  : account
                  ? ImportNewAccount(
                      name: _name.text.trim(),
                      activeFrom: _month(_from.text)!,
                      activeThrough: _through.text.isEmpty
                          ? null
                          : _month(_through.text),
                      liquidity: _liquidity,
                    )
                  : ImportNewCategory(
                      name: _name.text.trim(),
                      parent: parents[_parent],
                      isIncome: _parent == null ? _income : null,
                    ),
            );
          },
          child: const Text('Aplicar a la revisión'),
        ),
      ],
    );
  }
}
