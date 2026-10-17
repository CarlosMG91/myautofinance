import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/autofinance_ui.dart';
import '../domain/export_save.dart';
import 'export_controller.dart';

typedef ExportShell = Widget Function(
  Widget body,
  Future<bool> Function() canLeave,
  Future<bool> Function() back,
);

/// Formulario y resultado; los exportadores y el guardado pertenecen al controlador.
class ExportScreen extends StatefulWidget {
  const ExportScreen({
    super.key,
    required this.controller,
    required this.onReturn,
    this.shell,
  });
  final ExportController controller;
  final VoidCallback onReturn;
  final ExportShell? shell;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  ExportController get c => widget.controller;
  late final _from = TextEditingController(text: c.from);
  late final _through = TextEditingController(text: c.through);
  bool _guide = false,
      _allowPop = false,
      _asking = false,
      _exitRequested = false;

  @override
  void dispose() {
    _from.dispose();
    _through.dispose();
    c.dispose();
    super.dispose();
  }

  Future<bool> _canLeave() async {
    if (_asking) return false;
    if (!c.busy && !c.dirty) return true;
    _asking = true;
    final saving = c.phase == ExportPhase.saving;
    final preparing = c.phase == ExportPhase.preparing;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(
          saving
              ? '¿Salir durante el guardado?'
              : preparing
              ? '¿Cancelar la operación?'
              : '¿Descartar el borrador?',
        ),
        content: Text(
          saving
              ? 'El selector o la escritura están en curso. Esperaremos al resultado real; el archivo puede quedar guardado. Mantén la app abierta.'
              : preparing
              ? 'Se cancelará la preparación temporal. Tus datos y archivos guardados se conservan.'
              : 'Puedes continuar o descartar esta selección. Tus archivos guardados se conservan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(saving ? 'Seguir esperando' : 'Continuar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              saving
                  ? 'Solicitar salir y esperar'
                  : preparing
                  ? 'Cancelar operación'
                  : 'Descartar borrador',
            ),
          ),
        ],
      ),
    );
    _asking = false;
    if (!mounted || discard != true) return false;
    // Aunque la operación terminase con el diálogo abierto, se muestra su resultado.
    if (saving || preparing) {
      if (preparing) c.cancelPreparation();
      setState(() => _exitRequested = true);
      return false;
    }
    return true;
  }

  Future<bool> _back() async {
    if (_guide) {
      setState(() => _guide = false);
      return false;
    }
    if (!await _canLeave() || !mounted) return false;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReturn();
    });
    return true;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final body = _guide ? _guideBody() : _body();
      return PopScope(
        canPop: _allowPop,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _back,
            const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
                _back,
          },
          child: Focus(
            autofocus: true,
            child:
                widget.shell?.call(body, _canLeave, _back) ??
                Scaffold(
                  appBar: AppBar(
                    title: const Text('Exportación y portabilidad'),
                    leading: IconButton(
                      tooltip: 'Volver al origen',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: _back,
                    ),
                  ),
                  body: SafeArea(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: body,
                    ),
                  ),
                ),
          ),
        ),
      );
    },
  );

  Widget _body() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 16,
    children: [
      Text(
        c.mode == ExportMode.complete
            ? 'Exportar copia completa'
            : 'Exportar datos',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      Text(
        c.mode == ExportMode.complete
            ? 'Toda la base financiera SQLite para conservar y consultar.'
            : 'CSV legibles con los mismos signos que ves en la app.',
      ),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          AfAction(
            label: 'Exportar datos',
            onPressed: c.busy ? null : () => c.select(mode: ExportMode.data),
          ),
          AfAction(
            label: 'Exportar copia completa',
            onPressed: c.busy
                ? null
                : () => c.select(mode: ExportMode.complete),
          ),
        ],
      ),
      LayoutBuilder(
        builder: (context, constraints) {
          final cards = [_period(), _summary()];
          if (constraints.maxWidth < 800 ||
              MediaQuery.textScalerOf(context).scale(16) > 24) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: cards,
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 16,
            children: [for (final card in cards) Expanded(child: card)],
          );
        },
      ),
      if (c.mode == ExportMode.data)
        const Text(
          'CSV de lectura, distinto del CSV histórico de importación. Los presupuestos conservan el signo de la app. Estos CSV no se importan directamente ni reconstruyen una base.',
        ),
      if (c.busy)
        AfCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  c.phase == ExportPhase.preparing
                      ? 'Capturando una revisión coherente, generando y verificando el ZIP'
                      : 'Selector de destino y guardado del sistema en curso',
                ),
              ),
              const LinearProgressIndicator(
                semanticsLabel: 'Exportación en curso',
              ),
              const Text(
                'Mantén la app abierta. No se mostrará éxito hasta confirmar la escritura y el cierre.',
              ),
              if (_exitRequested)
                const Text(
                  'Salida solicitada. Espera al resultado y después vuelve al origen.',
                ),
              AfAction(
                label: c.phase == ExportPhase.preparing
                    ? 'Cancelar operación'
                    : 'Solicitar salir',
                onPressed: _canLeave,
              ),
            ],
          ),
        ),
      if (c.message != null)
        AfCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  c.message!,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (c.result case ExportSaved(:final location)) ...[
                if (location != null)
                  SelectableText(
                    'Ubicación facilitada por el sistema: $location',
                  )
                else
                  const Text(
                    'Ubicación no facilitada por el proveedor. Consulta el documento elegido en el selector.',
                  ),
                if ((c.result as ExportSaved).displayName
                    case final String name)
                  SelectableText('Nombre guardado: $name')
                else
                  Text(
                    'Nombre propuesto: ${c.suggestedName}. El nombre final depende del selector.',
                  ),
                Text(
                  'Contenido verificado: ${c.exportedMode == ExportMode.complete ? 'SQLite completo, manifest.json y LEEME.md' : 'siete CSV, diccionario.json, manifest.json y LEEME.md'}. Ámbito: ${c.exportedScope}.',
                ),
              ],
            ],
          ),
        ),
      if (c.capturedState != null)
        SelectableText(
          'Revisión capturada: ${c.capturedState!.revision}\nFecha de captura UTC: ${c.capturedAt!.toIso8601String()}',
        ),
      if (c.cleanupWarning != null)
        Semantics(liveRegion: true, child: Text(c.cleanupWarning!)),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          AfAction(
            label: c.result is ExportSaved
                ? 'Guardar nueva exportación'
                : c.message != null
                ? 'Reintentar guardado'
                : 'Guardar ZIP',
            variant: AfActionVariant.primary,
            onPressed: c.busy
                ? null
                : () {
                    _exitRequested = false;
                    c.save();
                  },
          ),
          AfAction(label: 'Volver al origen', onPressed: _back),
          AfAction(
            label: 'Consultar guía',
            onPressed: c.busy ? null : () => setState(() => _guide = true),
          ),
        ],
      ),
      const Text(
        'Se prepara y verifica el ZIP antes de abrir el selector. Exportar no modifica tus datos ni inicia una copia en Drive.',
      ),
    ],
  );

  Widget _period() => AfCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        Text(
          'Qué quieres incluir',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Material(
          color: Colors.transparent,
          child: RadioGroup<bool>(
            groupValue: c.mode == ExportMode.complete ? false : c.months,
            onChanged: (value) {
              if (!c.busy && c.mode == ExportMode.data) c.select(months: value);
            },
            child: Column(
              children: [
                RadioListTile<bool>(
                  value: false,
                  title: const Text('Todo el histórico'),
                  enabled: !c.busy && c.mode == ExportMode.data,
                ),
                RadioListTile<bool>(
                  value: true,
                  title: const Text('Rango de meses'),
                  enabled: !c.busy && c.mode == ExportMode.data,
                ),
              ],
            ),
          ),
        ),
        if (c.mode == ExportMode.complete)
          const Text(
            'El filtro no se aplica: la copia completa siempre incluye todo el histórico.',
          )
        else ...[
          TextField(
            key: const ValueKey('export-from'),
            controller: _from,
            enabled: !c.busy && c.months,
            decoration: const InputDecoration(
              labelText: 'Desde (AAAA-MM)',
              hintText: '2026-01',
            ),
            onChanged: (text) => c.select(from: text),
          ),
          TextField(
            key: const ValueKey('export-through'),
            controller: _through,
            enabled: !c.busy && c.months,
            decoration: const InputDecoration(
              labelText: 'Hasta (AAAA-MM)',
              hintText: '2026-12',
            ),
            onChanged: (text) => c.select(through: text),
          ),
          const Text(
            'Meses completos inclusivos. Movimientos por fecha de valor; presupuestos y fotos por mes.',
          ),
        ],
      ],
    ),
  );

  Widget _summary() => AfCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        Text(
          'Resumen del contenido',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text('Ámbito: ${c.scope}'),
        Text(
          c.mode == ExportMode.complete
              ? 'Base financiera SQLite completa, metadatos de verificación y guía LEEME. Incluye catálogos, movimientos, presupuestos, fotos y procedencia guardada. Sin sesión, credenciales ni estado Drive.'
              : 'Siete CSV: movimientos, presupuestos, fotos y sus valores, cuentas, categorías y liquidez histórica. Diccionario, guía LEEME y metadatos de verificación incluidos. IDs y relaciones conservados. Catálogos completos y liquidez también fuera del periodo elegido.',
        ),
        const Text(
          'Revisa el contexto antes de compartir. Las fotos son registros manuales. Un mes sin foto completa sigue «sin dato»; no se rellena con cero. Este resumen no certifica que tu patrimonio esté completo.',
        ),
      ],
    ),
  );

  Widget _guideBody() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 16,
    children: [
      Text(
        'Leer tus datos sin Autofinance',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const AfCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            Text('Para consultar los CSV'),
            Text(
              'Conserva el ZIP original. Consulta su LEEME y diccionario. Extrae en una carpeta nueva. Usa texto UTF-8, separador punto y coma, fechas ISO y EUR con decimal punto y dos decimales exactos.',
            ),
            Text(
              'Importa TODAS las columnas como Texto antes de cargar y desactiva las fórmulas y la detección de tipos. No abras con doble clic. Las comillas CSV no impiden ejecutar fórmulas. Si tu herramienta no permite desactivarlas, usa un editor de texto.',
            ),
            Text(
              'Relaciona registros por sus IDs. Los signos coinciden con la app. Los CSV no reconstruyen la base ni se importan directamente.',
            ),
            Text('Para recuperar una lectura de la copia completa'),
            Text(
              'Sigue el LEEME incluido: valida versión, inventario exacto, tamaños y hashes del ZIP antes de extraer. Rechaza rutas inesperadas, enlaces, duplicados o archivos incompletos. Extrae a una carpeta NUEVA y vacía de Windows, fuera de la instalación. También sirve para copias exportadas desde Android.',
            ),
            Text(
              'Abre autofinance.sqlite en modo solo lectura con SQLite estándar. Revisa sqlite_schema, las relaciones y las unidades indicadas en el LEEME. Los importes almacenados están en céntimos enteros.',
            ),
            Text(
              'Esta recuperación permite consultar datos. No sustituye la base activa ni restaura una instalación. No requiere root de Android. Las fotos ausentes o incompletas son «sin dato», distinto de un cero registrado. No calcules saldos desde movimientos.',
            ),
          ],
        ),
      ),
      AfAction(
        label: 'Volver al recorrido',
        onPressed: () => setState(() => _guide = false),
      ),
    ],
  );
}
