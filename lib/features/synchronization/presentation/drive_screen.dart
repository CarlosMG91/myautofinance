import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../ui/autofinance_ui.dart';
import '../domain/drive_download.dart';
import '../domain/drive_upload.dart';
import '../domain/installation_sync_state.dart';
import 'drive_controller.dart';

class DriveScreen extends StatefulWidget {
  const DriveScreen({
    super.key,
    required this.controller,
    required this.onReturn,
    required this.returnLabel,
    this.navigation,
    this.bottomNavigation,
    this.onOpenBackups,
    this.shell,
  });
  final DriveController controller;
  final VoidCallback onReturn;
  final String returnLabel;
  final Widget? navigation;
  final Widget? bottomNavigation;
  final VoidCallback? onOpenBackups;
  final Widget Function(Widget body)? shell;
  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> {
  final _downloadFocus = FocusNode();
  final _uploadFocus = FocusNode();
  bool _reviewing = false;
  DriveController get controller => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.refreshLocal();
    });
  }

  @override
  void dispose() {
    _downloadFocus.dispose();
    _uploadFocus.dispose();
    super.dispose();
  }

  String _date(DateTime? date) => date == null
      ? 'Desconocida'
      : '${DateFormat('dd/MM/yyyy · HH:mm', 'es_ES').format(date.toLocal())} · hora local';

  Widget _focusFrame(FocusNode focus, Widget child) => ListenableBuilder(
    listenable: focus,
    builder: (context, _) => Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          width: 2,
          color: focus.hasFocus ? AfTokens.focus : Colors.transparent,
        ),
      ),
      child: child,
    ),
  );

  Future<void> _run(bool upload) async {
    await controller.run(upload: upload, review: _review);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) (upload ? _uploadFocus : _downloadFocus).requestFocus();
    });
  }

  Future<bool> _review(DriveDownloadReview review) async {
    if (!mounted) return false;
    // La vista recibe los metadatos antes de continuar. La confirmación de
    // pérdida se reserva a cambios locales o relación desconocida, según EP-002.
    if (!review.requiresConfirmation) return true;
    _reviewing = true;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.pop(context, false),
        },
        child: AlertDialog(
          constraints: const BoxConstraints(maxWidth: 560),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          contentPadding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
          ),
          title: Semantics(
            namesRoute: true,
            child: Text('Descargar última copia'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cuenta: ${controller.snapshot.account ?? review.accountId}',
                ),
                Text(
                  'Versión remota: ${review.remote.version ?? "Desconocida"}',
                ),
                Text('Fecha: ${_date(review.remote.modifiedTime)}'),
                const SizedBox(height: 16),
                if (review.requiresConfirmation) Text(review.warning),
                const Text(
                  'Se creará un respaldo local recuperable antes de sustituir la base activa.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Descargar y sustituir'),
            ),
          ],
        ),
      ),
    );
    _reviewing = false;
    if (mounted) _downloadFocus.requestFocus();
    return accepted == true;
  }

  Widget _heading(String text) =>
      Text(text, style: Theme.of(context).textTheme.titleLarge);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final noCopy = controller.remoteKnowledge == DriveRemoteKnowledge.noCopy;
      final version = noCopy
          ? null
          : controller.observed?.version ?? controller.snapshot.version;
      final date = noCopy
          ? null
          : controller.observed?.modifiedTime ?? controller.snapshot.date;
      final remote = switch (controller.remoteKnowledge) {
        DriveRemoteKnowledge.unknown =>
          'Remoto desconocido · No se ha comprobado la copia',
        DriveRemoteKnowledge.noCopy => 'Sin copia en Drive',
        DriveRemoteKnowledge.known =>
          'Última copia conocida · Versión ${version ?? "desconocida"}',
      };
      final local = switch (controller.snapshot.localStatus) {
        SyncLocalStatus.clean => 'No',
        SyncLocalStatus.changed => 'Sí',
        SyncLocalStatus.pending => 'Operación pendiente de comprobar',
        SyncLocalStatus.contrastRequired =>
          'Pendientes de contrastar tras recuperación',
        SyncLocalStatus.unknown => 'Desconocidos',
      };
      final enabled = controller.available && !controller.busy;
      final versionsDiffer =
          version != null &&
          controller.snapshot.referenceVersion != null &&
          version != controller.snapshot.referenceVersion;
      final body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          if (widget.shell == null) ...[
            TextButton(
              onPressed: controller.busy ? null : widget.onReturn,
              child: Text(widget.returnLabel),
            ),
            _heading('Copia en Drive'),
          ],
          const Text(
            'Tu base está en este dispositivo. Subir copia y Descargar última copia '
            'son las únicas acciones que consultan o transfieren a Drive.',
          ),
          AfResponsiveGrid(
            columns: 2,
            minimumWidth: 320,
            children: [
              AfCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: [
                    _heading('Tu base local'),
                    Text(
                      'Cambios locales: $local',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    AfValueRow(
                      label: 'Cuenta',
                      value: Text(
                        controller.snapshot.account ?? 'Sin cuenta conectada',
                      ),
                    ),
                    AfValueRow(
                      label: 'Versión de referencia local',
                      value: AfNumericText(
                        controller.snapshot.referenceVersion ?? 'Desconocida',
                      ),
                    ),
                    const Text(
                      'La referencia identifica la copia de origen; '
                      'los cambios locales se comprueban por separado.',
                    ),
                  ],
                ),
              ),
              AfCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: [
                    _heading('Copia en Google Drive'),
                    Text(
                      remote,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    AfValueRow(
                      label: 'Fecha de la última copia conocida',
                      value: Text(noCopy ? 'Sin copia' : _date(date)),
                    ),
                    const Text(
                      'Información de la última acción manual. '
                      'Abrir esta pantalla no comprueba si Drive ha cambiado.',
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (controller.unavailableReason != null)
            AfStatus(
              kind: AfStatusKind.pending,
              message: controller.unavailableReason!,
            ),
          if (controller.recoveryBlocked)
            const AfStatus(
              kind: AfStatusKind.error,
              message: 'Acceso bloqueado. Abre Copias locales para recuperar la base.',
            ),
          if (controller.conflict || versionsDiffer)
            AfStatus(
              kind: controller.comparisonRequired && !versionsDiffer
                  ? AfStatusKind.pending
                  : AfStatusKind.divergence,
              message: controller.comparisonRequired && !versionsDiffer
                  ? 'La relación con la copia remota está pendiente de contrastar. '
                        'No se sobrescriben ni se mezclan automáticamente.'
                  : 'La copia local y la remota necesitan revisión. '
                        'No se sobrescriben ni se mezclan automáticamente.',
              action: controller.conflict
                  ? TextButton(
                      onPressed: controller.busy ? null : controller.keepLocal,
                      child: const Text('Conservar datos locales'),
                    )
                  : null,
            ),
          AfCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                _heading('Copia manual'),
                const Text(
                  'Subir guarda una copia de tu base local. '
                  'Descargar valida la copia remota y protege la base anterior antes de sustituirla.',
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _focusFrame(
                      _uploadFocus,
                      FilledButton(
                        focusNode: _uploadFocus,
                        onPressed: enabled ? () => _run(true) : null,
                        child: const Text('Subir copia'),
                      ),
                    ),
                    _focusFrame(
                      _downloadFocus,
                      OutlinedButton(
                        focusNode: _downloadFocus,
                        onPressed: enabled ? () => _run(false) : null,
                        child: const Text('Descargar última copia'),
                      ),
                    ),
                  ],
                ),
                const Text('No hay sincronización ni fusión automática.'),
              ],
            ),
          ),
          if (controller.busy)
            AfStatus(
              kind: AfStatusKind.loading,
              message: controller.phase,
              action: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_reviewing) const LinearProgressIndicator(),
                  TextButton(
                    onPressed: controller.cancellationAllowed && !_reviewing
                        ? controller.cancel
                        : null,
                    child: const Text('Cancelar operación'),
                  ),
                  if (!controller.cancellationAllowed)
                    const Text(
                      'La publicación está en curso; espera el resultado antes de salir.',
                    ),
                ],
              ),
            ),
          if (controller.message != null)
            AfStatus(
              kind: controller.conflict && !controller.comparisonRequired
                  ? AfStatusKind.divergence
                  : controller.error
                  ? AfStatusKind.error
                  : controller.completed
                  ? AfStatusKind.success
                  : AfStatusKind.pending,
              message: 'Última operación: ${controller.message}',
              action: controller.error
                  ? const Text(
                      'Reintenta manualmente con Subir copia o Descargar última copia.',
                    )
                  : null,
            ),
          if (controller.backupId != null)
            Text(
              'Respaldo recuperable en Copias locales: ${controller.backupId}',
            ),
          if (widget.onOpenBackups != null)
            AfCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  _heading('Recuperación en este dispositivo'),
                  const Text(
                    'Consulta y restaura copias locales, incluso si la base no puede abrirse. '
                    'Estas copias no se envían a Drive.',
                  ),
                  AfAction(
                    label: 'Abrir Copias locales',
                    onPressed: controller.busy ? null : widget.onOpenBackups,
                  ),
                ],
              ),
            ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Cómo se protegen las copias'),
            children: const [Text(driveUploadRaceNotice)],
          ),
        ],
      );
      if (widget.shell != null) {
        return PopScope(
          canPop: !controller.busy,
          child: widget.shell!(FocusTraversalGroup(child: body)),
        );
      }
      return PopScope(
        canPop: !controller.busy,
        child: Scaffold(
          body: Row(
            children: [
              if (widget.navigation != null) widget.navigation!,
              Expanded(
                child: SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: FocusTraversalGroup(child: body),
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: widget.bottomNavigation,
        ),
      );
    },
  );
}
