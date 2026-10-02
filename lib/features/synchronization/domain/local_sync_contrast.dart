/// Señal de instalación, independiente del linaje/revisión de SQLite.
final class LocalSyncContrast {
  const LocalSyncContrast({
    required this.restoreEpoch,
    required this.required,
    this.unreliable = false,
  });
  final String? restoreEpoch;
  final bool required;

  /// Diario en curso o catálogo ambiguo/dañado: no se puede acreditar una copia.
  final bool unreliable;
}

abstract interface class LocalSyncContrastReader {
  /// Sin red. Un estado ausente o ambiguo nunca acredita coincidencia remota.
  Future<LocalSyncContrast> read();
}
