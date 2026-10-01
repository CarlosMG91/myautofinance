# MA-TSK-042 · Evidencia y bloqueo externo

Fecha: 2026-10-01. Se usaron la épica y el ticket completos proporcionados por
el usuario, AGENTS.md, la base Flutter y el contrato EP-001 §7.1. Epic Board no
dispone de herramienta disponible y el inventario de control del navegador no
mostró navegadores o pestañas conectados. No se consultó ni modificó el tablero.

## Estado del aprovisionamiento

**Bloqueo externo documentado**, admitido por el criterio de aceptación.
No hay acceso autenticado a Google Cloud en esta sesión ni Cloud SDK (`gcloud`)
en PATH. El conector Drive disponible opera sobre archivos del usuario; no
administra proyectos, API habilitadas o clientes OAuth de la aplicación.
Usarlo no acreditaría los permisos de Autofinance.

No existe un APK local en `build/app/outputs/flutter-apk/app-debug.apk` ni el
keystore debug en la ubicación estándar de esta máquina. No se dispone de
huellas verificadas del APK que vaya a probarse. No se generan ni registran
huellas de ejemplo como credenciales reales.

| Criterio | Entrega / comprobación |
|---|---|
| Proyecto común y clientes Android/Windows configurados o bloqueo externo documentado | Bloqueo anterior y procedimiento reproducible en [OAuth Google](oauth-google.md); IDs `null`, clientes Android vacíos |
| Consentimiento `drive.file` sin permisos generales | Scope único en inventario y verificador; aplicación real en Cloud y consentimiento en dispositivo pendientes |
| Identificadores públicos separados de tokens/secretos | Inventario con esquema cerrado; no se consume como sesión ni se incluye en Flutter |
| Ninguna credencial personal o configuración sensible confirmada | Datos sintéticos en pruebas, protecciones Git y revisión de archivos propios |

El propietario debe crear o identificar el proyecto Autofinance, habilitar
Drive API, configurar marca/audiencia/testing y la cuenta tester, verificar
el APK efectivo, crear sus clientes Android y el cliente desktop y registrar
solo IDs/huellas públicos. Después ejecutar el verificador estricto. No se
necesitan contraseñas ni tokens para entregar esa evidencia pública.

El repositorio queda preparado para ese alta. No se afirma que OAuth esté
operativo ni que se haya realizado un consentimiento, login, acceso remoto,
creación de carpeta o intercambio de copia. La validación local de un
inventario declarado no sustituye la comprobación en Google.

## Comprobaciones locales

- `flutter --version`: Flutter 3.47.0 y Dart 3.13.0, SDK local existente en
  `.tools/flutter`, añadido al PATH solo para los comandos de esta sesión.
- `scripts/check-toolchain.ps1` y `flutter pub get --enforce-lockfile` correctos.
  `toolchain.json` y `pubspec.lock` no cambian.
- `node scripts/check-google-oauth.mjs`: contrato público válido y aviso
  explícito de bloqueo externo.
- `node --test scripts/tests/google-oauth-config.test.mjs`: **14 pruebas
  correctas**, con proyecto/huellas/IDs sintéticos. Cubren rechazo de permisos
  generales y appData, identidad innecesaria, campos sensibles en cada nivel,
  clientes de proyectos distintos, inventario incompleto, huellas/evidencia
  inválidas, paquete distinto y variantes Gradle que requieren revisión.
- `node scripts/check-google-oauth.mjs --require-configured`: salida **1**,
  rechazo esperado por bloqueo externo. La salida cero del modo normal no
  acredita aprovisionamiento.
- `scripts/check-quality.ps1` completo: 50 archivos Dart con formato correcto,
  análisis sin incidencias, **77 pruebas Flutter** y cuatro variantes de
  `APP_ENV` correctas. La prueba SQLite del recorrido MA-TSK-040 emite una
  advertencia de Drift por instancias múltiples; no produce fallos y no se ha
  cambiado ese código ajeno al ticket.
- `git check-ignore`: los siete nombres/rutas de ejemplo de material privado
  quedan ignorados, sin crear ni leer archivos personales.
- `git diff --check`: correcto. Solo se cambian inventario público, verificador,
  pruebas sintéticas, documentación y exclusiones preventivas de Git.

No se ejecutaron builds Windows/Android ni pruebas en dispositivos: no cambian
fuentes nativas, dependencias, Dart ni configuración de plataforma. No se ha
acreditado una firma Android, un consentimiento real ni acceso de la app a
Drive. El verificador es independiente de `check-quality.ps1` y del CI Flutter;
ejecutar sus comandos al modificar el inventario OAuth.
