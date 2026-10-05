import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import '../domain/budget_repository.dart';

String budgetDecimal(int cents) {
  final n = BigInt.from(cents).abs();
  return '${cents < 0
      ? '-'
      : cents > 0
      ? '+'
      : ''}${n ~/ BigInt.from(100)},${(n % BigInt.from(100)).toString().padLeft(2, '0')}';
}

String budgetEuro(int? cents) =>
    '${budgetTotal(cents == null ? null : BigInt.from(cents))}${cents == 0 ? ' (registrado)' : ''}';

String budgetTotal(BigInt? cents) {
  if (cents == null) return 'Sin presupuesto';
  final n = cents.abs();
  final units = (n ~/ BigInt.from(100)).toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]}.',
  );
  return '${cents.isNegative
      ? '−'
      : cents > BigInt.zero
      ? '+'
      : ''}$units,${(n % BigInt.from(100)).toString().padLeft(2, '0')} €';
}

int parseBudgetAmount(String value) {
  final text = value.trim().replaceAll('−', '-');
  if (!RegExp(r'^[+-]?\d+(?:[,.]\d{1,2})?$').hasMatch(text)) {
    throw const BudgetFailure(
      'Introduce un importe firmado, con hasta dos decimales. Vaciar no elimina la partida.',
      code: BudgetFailureCode.invalidAmount,
    );
  }
  final pieces = text
      .replaceAll(',', '.')
      .replaceAll(RegExp(r'^[+-]'), '')
      .split('.');
  final amount =
      BigInt.parse(pieces.first) * BigInt.from(100) +
      BigInt.parse(pieces.length == 1 ? '0' : pieces.last.padRight(2, '0'));
  final signed = text.startsWith('-') ? -amount : amount;
  if (signed < BigInt.parse('-9223372036854775808') ||
      signed > BigInt.parse('9223372036854775807')) {
    throw const BudgetFailure(
      'El importe está fuera del rango admitido.',
      code: BudgetFailureCode.invalidAmount,
    );
  }
  return signed.toInt();
}

String budgetError(Object error) {
  if (error is! BudgetFailure) {
    return 'No se pudo completar la operación. El borrador se conserva; reintenta.';
  }
  return [
    error.message,
    for (final c in error.conflicts)
      '${c.month.value.substring(0, 7)}: ${c.requestedPath} ↔ ${c.existingPath}',
    if (error.conflicts.isNotEmpty) 'Se conservan el borrador y las partidas previas. Resuelve el conflicto explícitamente antes de reintentar.',
  ].join('\n');
}

/// Protege también salida nativa; solo la ruta visible decide sobre el cierre.
abstract class BudgetDraftState<T extends StatefulWidget> extends State<T> {
  bool busy = false, confirming = false, allowPop = false;
  bool get dirty;
  bool get locked => busy || confirming || allowPop;
  late final AppLifecycleListener _lifecycle;
  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        if (locked) return AppExitResponse.cancel;
        if (ModalRoute.of(context)?.isCurrent != true) {
          return dirty ? AppExitResponse.cancel : AppExitResponse.exit;
        }
        return await discard() ? AppExitResponse.exit : AppExitResponse.cancel;
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<bool> ask(
    String title,
    String message,
    String action, {
    String cancel = 'Cancelar',
  }) async {
    if (confirming) return false;
    final focus = FocusManager.instance.primaryFocus;
    setState(() => confirming = true);
    final route = DialogRoute<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.all(16),
        title: Focus(
          autofocus: true,
          child: Semantics(header: true, child: Text(title)),
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    final result = await Navigator.of(context).push(route) ?? false;
    await route.completed;
    if (mounted) {
      setState(() => confirming = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && focus?.context != null) focus?.requestFocus();
      });
    }
    return result;
  }

  Future<bool> discard() async =>
      !dirty ||
      await ask(
        'Hay cambios sin guardar',
        'El borrador se conserva si sigues editando.',
        'Descartar cambios',
        cancel: 'Seguir editando',
      );
  Future<void> leave(VoidCallback action) async {
    if (locked || !await discard() || !mounted) return;
    setState(() => allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) action();
    });
  }
}
