# MA-TSK-242 · Verificación de almacenamiento

Ejecución del 2026-10-19. Base de código `8000052` más los cambios de este
ticket. El checkout contiene trabajo concurrente de sincronización y prototipos,
excluido del commit de MA-TSK-242. Los APK son debug, `APP_ENV=test`, privados e
ignorados por Git; no son una entrega de producción ni prueba de actualización.

## Alcance comprobado

- Flutter 3.47.0 / Dart 3.13.0; `check-toolchain.ps1` correcto. JDK 17 local,
  Android compile/target 36 y NDK 28.2.13676358 conservados. No hay cambios en
  `pubspec.lock`, `toolchain.json`, configuración OAuth, SQLite ni sus rutas.
- Formato de 505 archivos correcto y análisis estático sin incidencias.
- 84 pruebas específicas aprobadas: selectores CSV/XLS, flujo CSV con sesiones
  reemplazadas/rollback y almacén/proveedor/autorización Android. Las pruebas de
  autorización usan dobles y no acreditan una conexión Google real.
- 37 pruebas Node aprobadas: 28 del auditor de almacenamiento y 9 del contrato
  APK. Incluyen recursos ausentes, dominios omitidos, rutas parciales, includes,
  permisos adicionales y proveedor/host de instrumentación accidental en release.
- APK debug universal compilado con JDK 17 y `APP_ENV=test`. El auditor lee su
  manifiesto y recursos **compilados** con aapt2 y acredita las exclusiones en
  los nueve dominios, antes de API 31 y para cloud/device-transfer API 31+.
- Inspector independiente del contrato APK: correcto, sin problemas; paquete
  invariable, `0.1.0+1`, mínimo 24, compile/target 36 y ABI `arm64-v8a`,
  `armeabi-v7a`, `x86_64`. Firma debug comprobada, solo inspección técnica,
  `completeDelivery=false`; no prueba un incremento de versión.
- Compilación Windows release `--no-pub --dart-define=APP_ENV=test`: correcta,
  en build aislado. No se instala ni distribuye; las fuentes Windows no cambian.
- Permisos solicitados efectivos: `INTERNET`, `USE_BIOMETRIC`, `USE_FINGERPRINT`
  y el permiso interno `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`. No aparecen
  almacenamiento amplio, medios o `REQUEST_INSTALL_PACKAGES`. La protección
  `MANAGE_DOCUMENTS` del proveedor sintético debug no es un permiso solicitado.

## Ejecución nativa y límites

El único dispositivo disponible es un emulador `sdk_gphone64_x86_64`, API 37,
páginas de 4096 bytes. Se comprobó que Autofinance no estaba instalada antes de
instalar el debug sintético. No hay teléfono físico conectado; no se ha ejecutado
un APK production, API 24, runtime API 36, 16 KB o migración entre versiones.

Certificado **debug** de app/runner usados:
`b5ef2aa1489a61a0698549d0cf1d598a6639a49156d7723faf9eb75c860d38e8` (SHA-256).
No es la identidad de distribución de EP-029. La primera instrumentación se
rechazó por diferencia de certificados debug al compilar con configuraciones
locales distintas; se conservó la instalación y se recompiló con la misma
configuración, sin forzar firma, uninstall ni clear-data. Se corrigió también
la ubicación/protección del proveedor sintético para cumplir las condiciones
nativas de `DocumentsProvider`; solo se incluye en debug.

El runner completó **101 comprobaciones nativas**, con salida raw
`INSTRUMENTATION_RESULT: stream=MA-TSK-242: 101 native checks passed` e
`INSTRUMENTATION_CODE: -1`. Lee URI del proveedor local Downloads y del
`DocumentsProvider` sintético, conserva exactamente los bytes CSV/XLS, diferencia
cancelación/denegación/desaparición/lectura parcial y rechaza `file://`. Comprueba
petición ocupada, resultado duplicado, detach con lectura pendiente y respuesta
tardía que no completa la petición de otra instancia. Verifica también recursos
empaquetados, permisos y reapertura/corrupción del registro AES-GCM, sin borrado
silencioso. También abre el selector oficial, elige la raíz documental sintética
y `fixture.csv`, verifica sus bytes y la pausa/reanudación real de la Activity;
vuelve a abrir para XLS, cancela con Back y comprueba el regreso. El host es solo
debug, no exportado, sin Flutter/SQLite. No usa Google ni toca la sesión habitual.

APK debug ensayado (hash SHA-256):
`de04e9a143ee49efcc95c108696feca4f46170ecbb4aad1f337d40a3023ef046`.
El soporte de prueba se conserva en el emulador; no se desinstala ni borra.

Se ejecutó además `:app:processReleaseResources`, **correcto**, sin tareas de
empaquetado/firma ni material de producción. Se convirtió su archivo de recursos
protobuf a binario mediante `aapt2 convert --output-format binary` y se auditó:
`debuggable=false`, mismas exclusiones/permisos y proveedor sintético ausente.
Esto acredita manifiesto y recursos release procesados, **no un APK release
ejecutable**. Se conserva la comprobación del APK production final en T07/T09.

## Calidad global

`scripts/check-quality.ps1`, con configuración/build aislados y acceso autorizado
a pub.dev: versiones, `--enforce-lockfile`, formato y análisis correctos. La
suite termina en **18:22, 2005 aprobadas y 8 fallidas**; el script devuelve error,
por lo que **la calidad global no está aprobada**. Fallos:

| Archivo | Casos fallidos |
| --- | --- |
| `test/drilldowns/report_drilldown_journey_test.dart` | Tres informes SQLite Windows; `StateError: No element` en `ensureVisible` del guion, línea 171. |
| `test/movements/pending_lifecycle_test.dart` | Windows tabla y Android tarjetas; `StateError: No element` en el guion, línea 144. |
| `test/redesign_integration_test.dart` | Rediseño integrado 412/1; Inicio, edición, retorno y rutas. |
| `test/synchronization/local_recovery_journey_test.dart` | Dos manuales/restauración/reinicio; fallo de disco tras instalar; cuarta fallida y retención; candidata truncada. |

Esos módulos y guiones no cambian en este ticket. No se afirma que los fallos
sean previos o que la suite esté verde: el checkout incluye cambios concurrentes
que se conservan, y no se corrigen fuera del alcance. El log completo queda en
`.tools/242-quality-complete.log` (privado, ignorado).

El script no alcanza su bucle final de arranque porque falla la suite; se ejecuta
ese bucle por separado: **development, test, production e invalid-synthetic,
una prueba aprobada en cada configuración**. Las 84 pruebas específicas y las
101 comprobaciones Android de este ticket sí están aprobadas.

## Incidencias del entorno

La primera resolución online/calidad en sandbox falló al consultar advisories
de pub.dev (`SocketException`, errno 10057); la resolución offline mantuvo el
lockfile. La revisión automática de permisos falló temporalmente por capacidad
de su servicio, no por una decisión de inseguridad. Los reintentos autorizados
permitieron acceder al SDK, Gradle y pub.dev sin cambiar versiones.

La primera suite general, con configuración Flutter heredada y ejecutada en
sandbox, terminó con 585 fallos. Una ejecución simultánea intentó reutilizar
su ruta de assets nativos bloqueada. No se atribuye esa ejecución al resultado
final: se repite `check-quality.ps1` con configuración/build aislados y permisos
necesarios. También se repitieron secuencialmente app e instrumentación después
de un bloqueo de archivo nativo entre builds concurrentes.

## Pendiente, sin sustituciones sintéticas

- Proveedor documental de uso en teléfono (por ejemplo, Drive) y recreación/muerte
  real de Activity/proceso, sin datos parciales. El selector oficial, selección
  documental sintética, Back y pausa/reanudación sí se probaron en el emulador;
  el runner no verifica la UI Flutter completa ni un proveedor remoto.
- Conservación real SQLite/copias/estado Drive/Keystore N→N+1 y nueva instalación
  en teléfono ARM64, con APK production exacto, firma estable y código creciente:
  T07/T09. No se cambia ni limpia el almacén real para suplir esa evidencia.
- Cloud/device-transfer OEM: política explícita empaquetada, sin ensayo de
  transferencias de todos los fabricantes ni promesa de control universal.
- Openbank sigue bloqueado por la entrega real de EP-014/MA-TSK-131, tal como
  documenta su [verificación de reapertura](../ep-014/verificacion-reapertura-131.md).
  No hay muestra accesible ni lector/adaptador/recorrido que probar en este
  ticket. No se ha inventado un XLS o atribuido esa carencia a Android.
- Google real y artefacto final quedan en T03/T07/T09. Ningún build, selector o
  proveedor falso cierra esos criterios ni MA-TSK-245.

El [contrato y los comandos](almacenamiento-android.md) permiten repetir la
auditoría sobre el APK final. No se modifican estados del tablero ni se declara
cerrada EP-029.
