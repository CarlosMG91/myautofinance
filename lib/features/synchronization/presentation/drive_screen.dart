import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

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
  });
  final DriveController controller;
  final VoidCallback onReturn;
  final String returnLabel;
  final Widget? navigation;
  final Widget? bottomNavigation;
  final VoidCallback? onOpenBackups;
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
          color: focus.hasFocus ? const Color(0xff005fcc) : Colors.transparent,
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final width = MediaQuery.sizeOf(context).width;
      final version =
          controller.observed?.version ?? controller.snapshot.version;
      final date = controller.remoteKnowledge == DriveRemoteKnowledge.noCopy
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
      final content = SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(width < 600 ? 16 : 24),
              child: FocusTraversalGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextButton(
                      onPressed: controller.busy ? null : widget.onReturn,
                      child: Text(widget.returnLabel),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Copia en Drive',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      color: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xffd6dee6)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Cuenta: ${controller.snapshot.account ?? "Sin cuenta conectada"}',
                              ),
                              const SizedBox(height: 12),
                              Text(remote),
                              Text(
                                'Fecha de la última copia conocida: ${_date(date)}',
                              ),
                              if (controller.conflict ||
                                  (version != null &&
                                      controller.snapshot.referenceVersion !=
                                          version))
                                Text(
                                  'Versión de referencia local: ${controller.snapshot.referenceVersion ?? "Desconocida"}',
                                ),
                              const SizedBox(height: 12),
                              Text('Cambios locales: $local'),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Solo se consulta o transfiere al pulsar un botón. No hay fusión automática.',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      driveUploadRaceNotice,
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    if (controller.unavailableReason != null)
                      Text(controller.unavailableReason!),
                    if (controller.recoveryBlocked)
                      const Text(
                        'Acceso bloqueado. Abre Copias locales para recuperar la base.',
                      ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _focusFrame(
                          _uploadFocus,
                          FilledButton(
                            onPressed: enabled ? () => _run(true) : null,
                            focusNode: _uploadFocus,
                            child: const Text('Subir copia'),
                          ),
                        ),
                        if (controller.recoveryBlocked &&
                            widget.onOpenBackups != null)
                          OutlinedButton(
                            onPressed: controller.busy
                                ? null
                                : widget.onOpenBackups,
                            child: const Text('Abrir Copias locales'),
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
                    if (controller.busy) ...[
                      const SizedBox(height: 16),
                      if (!_reviewing) const LinearProgressIndicator(),
                      Semantics(
                        liveRegion: true,
                        child: Text(controller.phase),
                      ),
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
                    if (controller.message != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          'Última operación: ${controller.message}',
                          style: TextStyle(
                            color: controller.error
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                        ),
                      ),
                      if (controller.backupId != null)
                        Text(
                          'Respaldo recuperable en Copias locales: ${controller.backupId}',
                        ),
                      if (controller.conflict)
                        TextButton(
                          onPressed: controller.busy
                              ? null
                              : controller.keepLocal,
                          child: const Text('Conservar datos locales'),
                        ),
                      if (controller.error)
                        const Text(
                          'Reintenta manualmente con Subir copia o Descargar última copia.',
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      return PopScope(
        canPop: !controller.busy,
        child: Scaffold(
          body: Row(
            children: [
              if (widget.navigation != null) widget.navigation!,
              Expanded(child: content),
            ],
          ),
          bottomNavigationBar: widget.bottomNavigation,
        ),
      );
    },
  );
}
