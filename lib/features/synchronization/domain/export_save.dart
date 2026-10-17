/// Guarda un ZIP preparado y cerrado. El llamante conserva su temporal hasta
/// recibir el resultado y lo libera también tras cancelación o error.
abstract interface class ExportSaver {
  Future<ExportSaveResult> save(ExportSaveRequest request);
}

final class ExportSaveRequest {
  ExportSaveRequest({required this.zipPath, required this.suggestedName}) {
    if (zipPath.isEmpty ||
        zipPath.contains('\u0000') ||
        !RegExp(r'^autofinance-(datos|copia|prueba)(-[0-9TZ_-]+)?\.zip$')
            .hasMatch(suggestedName)) {
      throw ArgumentError('Se requiere un ZIP y un nombre neutro Autofinance.');
    }
  }

  final String zipPath;
  final String suggestedName;
  String get mimeType => 'application/zip';
}

sealed class ExportSaveResult {
  const ExportSaveResult();
}

final class ExportSaved extends ExportSaveResult {
  const ExportSaved({this.location, this.displayName});

  /// Ruta Windows o URI Android, nunca una ruta ficticia para un proveedor.
  final String? location;

  /// Nombre final facilitado por el sistema/proveedor, si está disponible.
  final String? displayName;
}

final class ExportSaveCancelled extends ExportSaveResult {
  const ExportSaveCancelled();
}

enum ExportSaveFailureCode {
  accessDenied,
  noSpace,
  conflict,
  unavailable,
  invalidSource,
  writeFailed,
  busy,
}

final class ExportSaveFailed extends ExportSaveResult {
  const ExportSaveFailed(this.code, {this.incompleteMayRemain = false});
  final ExportSaveFailureCode code;
  final bool incompleteMayRemain;

  String get message => switch (code) {
    ExportSaveFailureCode.accessDenied => 'No hay permiso para guardar el ZIP.',
    ExportSaveFailureCode.noSpace => 'No hay espacio para guardar el ZIP.',
    ExportSaveFailureCode.conflict =>
      'El destino ya existe. Elige un nombre nuevo.',
    ExportSaveFailureCode.unavailable =>
      'El destino no está disponible o se ha desconectado.',
    ExportSaveFailureCode.invalidSource =>
      'El ZIP temporal no está disponible. Prepara de nuevo la exportación.',
    ExportSaveFailureCode.writeFailed =>
      'No se pudo terminar de guardar el ZIP.',
    ExportSaveFailureCode.busy => 'Ya hay un guardado en curso.',
  };
}
