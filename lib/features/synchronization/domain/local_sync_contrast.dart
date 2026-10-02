/// Señal de instalación, independiente del linaje/revisión de SQLite.
final class LocalSyncContrast {
  const LocalSyncContrast({required this.restoreEpoch, required this.required});
  final String? restoreEpoch;
  final bool required;
}

abstract interface class LocalSyncContrastReader {
  /// Sin red. Un estado ausente o ambiguo nunca acredita coincidencia remota.
  Future<LocalSyncContrast> read();
}
