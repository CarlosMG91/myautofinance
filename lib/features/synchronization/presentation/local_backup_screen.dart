import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/local_backup_catalog.dart';
import '../domain/local_backup_creation.dart';
import '../domain/local_restore.dart';
import '../domain/local_restore_candidate.dart';
import 'local_backup_controller.dart';

class LocalBackupScreen extends StatefulWidget {
  const LocalBackupScreen({
    super.key,
    required this.controller,
    required this.onOpenDetail,
    required this.onReturn,
    required this.returnLabel,
    this.backupId,
    this.navigation,
    this.bottomNavigation,
  });

  final LocalBackupController controller;
  final String? backupId;
  final ValueChanged<String> onOpenDetail;
  final VoidCallback onReturn;
  final String returnLabel;
  final Widget? navigation;
  final Widget? bottomNavigation;

  @override
  State<LocalBackupScreen> createState() => _LocalBackupScreenState();
}

class _LocalBackupScreenState extends State<LocalBackupScreen> {
  LocalBackupController get controller => widget.controller;
  final _createFocus = FocusNode();
  final _restoreFocus = FocusNode();
  final _deleteFocus = FocusNode();

  @override
  void dispose() {
    _createFocus.dispose();
    _restoreFocus.dispose();
    _deleteFocus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && controller.listing == null && !controller.busy) {
        controller.refresh();
      }
    });
  }

  String _date(DateTime date) {
    final local = date.toLocal();
    final offset = local.timeZoneOffset;
    final minutes = offset.inMinutes.abs();
    final zone =
        'UTC${offset.isNegative ? '−' : '+'}'
        '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
        '${(minutes % 60).toString().padLeft(2, '0')}';
    return '${DateFormat('dd/MM/yyyy · HH:mm', 'es_ES').format(local)} · $zone';
  }

  String _origin(LocalBackupCatalogEntry entry) =>
      entry.origin == LocalBackupOrigin.manual
      ? 'Manual · Esta instalación'
      : 'Automática · Antes de restaurar · Esta instalación';

  String _size(LocalBackupCatalogEntry entry) =>
      '${NumberFormat.decimalPattern('es_ES').format(entry.sizeBytes)} bytes';

  bool _usable(LocalBackupCatalogEntry entry) =>
      entry.availability == LocalBackupAvailability.present &&
      entry.validation != LocalBackupValidationState.invalid &&
      entry.validation != LocalBackupValidationState.incompatible;

  String _validation(LocalBackupCatalogEntry entry) {
    if (entry.availability != LocalBackupAvailability.present) {
      return switch (entry.availability) {
        LocalBackupAvailability.missing => 'No utilizable · Falta el archivo',
        LocalBackupAvailability.incomplete =>
          'No utilizable · Archivo incompleto',
        LocalBackupAvailability.quarantined =>
          'No utilizable · Archivo aislado',
        LocalBackupAvailability.deletionPending => 'Eliminación pendiente',
        LocalBackupAvailability.present => '',
      };
    }
    return switch (entry.validation) {
      LocalBackupValidationState.valid => 'Última comprobación correcta',
      LocalBackupValidationState.pending => 'Pendiente de comprobar',
      LocalBackupValidationState.invalid =>
        'No utilizable · Comprobación fallida',
      LocalBackupValidationState.incompatible => 'No utilizable · Incompatible',
      LocalBackupValidationState.unavailable =>
        'No se pudo comprobar el archivo',
    };
  }

  String _issue(String code) {
    for (final issue in LocalRestoreCandidateIssue.values) {
      if (issue.name == code) return issue.message;
    }
    return switch (code) {
      'missingFile' => 'Falta un archivo de la copia.',
      'incompleteFile' => 'El archivo está incompleto.',
      'storageFailure' => LocalBackupController.storageMessage,
      _ => 'La última comprobación no pudo acreditar una copia válida. Se validará de nuevo antes de restaurar.',
    };
  }

  Future<bool> _confirm({
    required String title,
    required String explanation,
    required String action,
    bool acknowledge = false,
    FocusNode? returnFocus,
  }) async {
    var accepted = false;
    final previousFocus = returnFocus ?? FocusManager.instance.primaryFocus;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          constraints: const BoxConstraints(maxWidth: 560),
          insetPadding: const EdgeInsets.all(16),
          scrollable: true,
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(explanation),
              if (acknowledge)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'Entiendo que la base activa volverá a esta fecha.',
                  ),
                  value: accepted,
                  onChanged: (value) => update(() => accepted = value ?? false),
                ),
            ],
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: acknowledge && !accepted
                  ? null
                  : () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ),
    );
    if (mounted) previousFocus?.requestFocus();
    return result ?? false;
  }

  Future<void> _create() async {
    _createFocus.requestFocus();
    final confirmed = await _confirm(
      title: 'Crear copia local',
      returnFocus: _createFocus,
      explanation:
          'Se guardará una copia completa y consistente del estado actual '
          'en esta instalación. Se verificará antes de aparecer en la lista. '
          'La copia será manual y se conservará hasta que usted la elimine expresamente.',
      action: 'Crear copia',
    );
    if (confirmed && mounted) await controller.create();
  }

  Future<void> _restore(LocalBackupCatalogEntry entry) async {
    _restoreFocus.requestFocus();
    final confirmed = await _confirm(
      title: '¿Restaurar esta copia?',
      returnFocus: _restoreFocus,
      explanation:
          '${_date(entry.createdAtUtc)}\n${_origin(entry)}\n\n'
          'Se sustituirán todos los datos actuales: movimientos, presupuestos, '
          'categorías, fichas y fotos. Los cambios posteriores dejarán de verse en la base activa.\n\n'
          '${controller.activeAvailable ? 'Antes de sustituirla se guardará una copia automática del estado actual. Si no se puede proteger, la restauración no continúa.' : 'Se conservarán aislados los archivos originales de la base dañada, si existen. No se puede prometer que sean restaurables.'}\n\n'
          'La copia se validará de nuevo. No se mezclan bases ni se conecta a Drive.',
      action: 'Restaurar copia',
      acknowledge: true,
    );
    if (mounted) await controller.restore(entry.backupId, confirmed: confirmed);
  }

  Future<void> _delete(LocalBackupCatalogEntry entry) async {
    _deleteFocus.requestFocus();
    final confirmed = await _confirm(
      title: '¿Eliminar esta copia local?',
      returnFocus: _deleteFocus,
      explanation:
          '${_date(entry.createdAtUtc)}\n${_origin(entry)}\n\n'
          'Esta acción elimina solo esta copia y no modifica la base activa. '
          'No se podrá usar de nuevo para recuperar datos. '
          'Antes del borrado se comprobará que hay otra copia utilizable.',
      action: 'Eliminar copia',
    );
    if (confirmed && mounted) await controller.delete(entry.backupId);
  }

  Widget _notice(String text, {bool error = false}) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: error ? const Color(0xfffcedef) : const Color(0xffeaf3fb),
        border: Border.all(
          color: error ? const Color(0xff9f2733) : const Color(0xffc0cad5),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: error ? const Color(0xff9f2733) : const Color(0xff17212b),
        ),
      ),
    ),
  );

  Widget _panel(List<Widget> children) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 8),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xffc0cad5)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );

  Widget _detail(LocalBackupCatalogEntry entry) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading('Copia del ${_date(entry.createdAtUtc)}'),
      _panel([
        _heading('Información de la copia'),
        Text('Identificador: ${entry.backupId}'),
        Text('Fecha de creación: ${_date(entry.createdAtUtc)}'),
        Text('Origen: ${_origin(entry)}'),
        Text('Tamaño: ${_size(entry)}'),
        Text('Última comprobación: ${_validation(entry)}'),
        Text(
          entry.checkedAtUtc == null
              ? 'Sin fecha de comprobación'
              : _date(entry.checkedAtUtc!),
        ),
        const Text(
          'La última comprobación no garantiza que el archivo siga intacto.',
        ),
        Text(
          'Conservación: ${entry.origin == LocalBackupOrigin.manual ? 'Indefinida, hasta eliminación expresa.' : 'Tres automáticas tras restauraciones correctas, sujetas a conservación segura.'}',
        ),
        if (entry.issue != null)
          Text('Motivo registrado: ${_issue(entry.issue!)}'),
      ]),
      _notice(
        _usable(entry)
            ? 'Restaurar sustituye todos los datos actuales. La versión anterior se protege antes del intercambio. Una copia antigua compatible se adapta y comprueba en una copia de trabajo; el original se conserva.'
            : 'Esta copia no se puede restaurar. Se conserva su ficha y la base activa no se ha modificado. Seleccione otra copia.',
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton(
            focusNode: _restoreFocus,
            onPressed: _usable(entry) && !controller.recoveryBlocked
                ? () => _restore(entry)
                : null,
            child: const Text('Restaurar esta copia'),
          ),
          OutlinedButton(
            focusNode: _deleteFocus,
            onPressed: controller.recoveryBlocked ? null : () => _delete(entry),
            child: const Text('Eliminar copia…'),
          ),
        ],
      ),
    ],
  );

  Widget _catalog(bool wide) {
    final listing = controller.listing;
    if (listing == null ||
        listing.status == LocalBackupCatalogStatus.unavailable ||
        listing.status == LocalBackupCatalogStatus.incompatible) {
      return _panel([
        _heading('No se pudo leer el catálogo'),
        const Text(
          'No se ha creado una base vacía ni se han borrado archivos.',
        ),
        if (listing?.incidents.isNotEmpty == true)
          _notice(
            'Hay archivos incompletos, aislados o incidencias de almacenamiento. No se presentan como copias válidas; se conservan para revisión.',
          ),
      ]);
    }
    if (listing.entries.isEmpty) {
      return _panel([
        _heading('Todavía no hay copias locales'),
        Text(
          controller.activeAvailable
              ? 'Cree una copia del estado actual para poder recuperarlo más adelante.'
              : 'No hay una copia local disponible para recuperar. Los archivos originales se conservan.',
        ),
        if (listing.incidents.isNotEmpty)
          _notice(
            'Hay archivos incompletos, aislados o incidencias de almacenamiento. No se presentan como copias válidas; se conservan para revisión.',
          ),
      ]);
    }
    final entries = [...listing.entries]
      ..sort((a, b) => b.creationOrder.compareTo(a.creationOrder));
    return _panel([
      _heading('Copias en esta instalación'),
      const Text(
        'Más recientes primero · Fechas en hora local con zona indicada. '
        'Se validará de nuevo antes de restaurar.',
      ),
      if (wide)
        Table(
          columnWidths: const {
            0: FlexColumnWidth(1.2),
            1: FlexColumnWidth(1.4),
            2: FlexColumnWidth(.8),
            3: FlexColumnWidth(1.3),
            4: FlexColumnWidth(1),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              children: [
                for (final title in [
                  'Fecha y hora',
                  'Origen',
                  'Tamaño',
                  'Estado',
                  'Acción',
                ])
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
              ],
            ),
            for (final entry in entries)
              TableRow(
                children: [
                  for (final text in [
                    _date(entry.createdAtUtc),
                    _origin(entry),
                    _size(entry),
                    _validation(entry),
                  ])
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(text, style: const TextStyle(fontSize: 14)),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: _openButton(entry),
                  ),
                ],
              ),
          ],
        )
      else
        for (final entry in entries)
          _panel([
            Text(
              _date(entry.createdAtUtc),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(_origin(entry)),
            Text('Tamaño: ${_size(entry)}'),
            Text(_validation(entry)),
            Text(
              'Comprobada: ${entry.checkedAtUtc == null ? 'sin fecha' : _date(entry.checkedAtUtc!)}',
            ),
            _openButton(entry),
          ]),
      if (listing.incidents.isNotEmpty)
        _notice(
          'Hay ${listing.incidents.length} incidencias en el almacenamiento. '
          'Los archivos incompletos o aislados no se adoptan como copias válidas. '
          'Se conservan los archivos y las fichas disponibles para revisión.',
        ),
    ]);
  }

  Widget _openButton(LocalBackupCatalogEntry entry) => Semantics(
    label: 'Copia ${entry.backupId}, ${_date(entry.createdAtUtc)}',
    child: OutlinedButton(
      onPressed: () => widget.onOpenDetail(entry.backupId),
      child: const Text('Ver detalle'),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => PopScope(
      canPop: !controller.busy,
      child: Scaffold(
        bottomNavigationBar: controller.busy ? null : widget.bottomNavigation,
        body: SafeArea(
          child: Row(
            children: [
              if (!controller.busy && widget.navigation != null)
                widget.navigation!,
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final screenWidth = MediaQuery.sizeOf(context).width;
                    final wide = screenWidth >= 840;
                    final margin = screenWidth >= 1200
                        ? 32.0
                        : screenWidth >= 600
                        ? 24.0
                        : 16.0;
                    final entries = controller.listing?.entries ?? [];
                    LocalBackupCatalogEntry? selected;
                    for (final entry in entries) {
                      if (entry.backupId == widget.backupId) selected = entry;
                    }
                    return SingleChildScrollView(
                      padding: EdgeInsets.all(margin),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: screenWidth < 840 && screenWidth >= 600
                                ? 720
                                : 1440,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (controller.busy ||
                                  controller.listing == null &&
                                      controller.error == null) ...[
                                _heading(
                                  controller.progress ??
                                      'Leyendo catálogo local…',
                                ),
                                const LinearProgressIndicator(),
                                _notice(
                                  'No cierre la app. Espere el resultado seguro antes de iniciar otra operación.',
                                ),
                              ] else ...[
                                if (controller.activeAvailable ||
                                    widget.backupId != null)
                                  TextButton(
                                    onPressed: widget.onReturn,
                                    child: Text(widget.returnLabel),
                                  ),
                                _heading(
                                  widget.backupId == null
                                      ? 'Copias locales'
                                      : 'Detalle de copia local',
                                ),
                                const Text(
                                  'Gestión / Copias locales · Almacenamiento privado de esta instalación',
                                ),
                                if (!controller.activeAvailable) ...[
                                  _notice(
                                    'No se puede abrir la base activa. ${controller.recoveryBlocked ? 'El acceso está bloqueado. Reinicia la app para resolver la recuperación o usa una versión compatible.' : 'Puede recuperar una copia local válida.'} '
                                    'Los archivos dañados se conservarán aislados; no se presentarán como una copia válida. '
                                    '${controller.startupMessage ?? ''}',
                                    error: true,
                                  ),
                                  if (controller.retryStartup != null &&
                                      !controller.recoveryBlocked)
                                    OutlinedButton(
                                      onPressed: controller.retryOpen,
                                      child: const Text('Reintentar apertura'),
                                    ),
                                ],
                                if (controller.error != null)
                                  _notice(controller.error!, error: true),
                                if (controller.message != null)
                                  _notice(controller.message!),
                                if (controller.restoreResult?.status ==
                                    LocalRestoreStatus.restored) ...[
                                  _notice(
                                    controller
                                                .restoreResult!
                                                .previousBackupId ==
                                            null
                                        ? 'Los archivos originales dañados o ausentes no se presentan como una copia válida. Los originales aislados se conservan fuera de la retención automática.'
                                        : 'El estado anterior se conserva en una copia automática.',
                                  ),
                                  if (controller.restoreResult!.previousBackupId
                                      case final id?)
                                    OutlinedButton(
                                      onPressed: () => widget.onOpenDetail(id),
                                      child: const Text('Ver copia anterior'),
                                    ),
                                  _notice(
                                    'Contraste con Drive pendiente. Una futura acción manual deberá contrastar la versión remota. No se ha realizado ninguna conexión.',
                                  ),
                                  if (controller
                                      .restoreResult!
                                      .maintenancePending)
                                    _notice(
                                      'Limpieza pendiente. Se conservan más copias hasta que sea seguro limpiar.',
                                    ),
                                ],
                                if (widget.backupId == null) ...[
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      FilledButton(
                                        focusNode: _createFocus,
                                        onPressed:
                                            controller.activeAvailable &&
                                                !controller.recoveryBlocked
                                            ? _create
                                            : null,
                                        child: const Text('Crear copia'),
                                      ),
                                      OutlinedButton(
                                        onPressed: controller.refresh,
                                        child: const Text(
                                          'Reintentar catálogo',
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (!controller.activeAvailable)
                                    const Text(
                                      'Crear copia no está disponible hasta que la base activa pueda usarse.',
                                    ),
                                  _catalog(wide),
                                  _notice(
                                    'Qué se conserva\nLas copias manuales permanecen hasta eliminación expresa. '
                                    'Se conservan las tres automáticas más recientes anteriores a restauraciones correctas. '
                                    'Un intento fallido no elimina ninguna; si no es seguro limpiar, se conservan más.\n'
                                    'Estas copias permanecen en este dispositivo: no protegen frente a su pérdida o a la eliminación de los datos de la app.',
                                  ),
                                ] else if (selected != null)
                                  _detail(selected)
                                else
                                  _notice(
                                    'No se pudo abrir este detalle. La copia no está disponible en el catálogo. Vuelva a la lista y reintente.',
                                    error: true,
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
