# MA-TSK-069 · Verificación de sincronización entre instalaciones

Fecha: 2026-10-02. **Entrega automatizada; aceptación nativa pendiente.**

Se revisaron el ticket suministrado, su dependencia MA-TSK-068, el caso I de
EP-001 y la captura local de Epic Board `.tools/board-059.json`, tablero
**My autofinance**, MA-EPIC-060 / MA-TSK-069. La captura conserva un estado
antiguo; no hay un conector Epic Board disponible para consultar o actualizar
el estado vivo. No se ha marcado el ticket ni la épica como completados.

## Recorrido automatizado

`test/synchronization/drive_two_installations_test.dart` usa dos directorios
privados, dos bases SQLite, dos sesiones de la misma cuenta sintética y un
servidor HTTP Drive simulado compartido. Las composiciones públicas de subida,
descarga segura, estado, reconciliación y recuperación son las de producción.
Los nombres Windows/Android identifican instalaciones lógicas: estas pruebas
de servicios no ejecutan OAuth, plugins ni binarios nativos de ambas plataformas.

La fixture `seedRecoveryReference` reproduce los registros financieros
normalizados de EP-001; no demuestra el flujo de importación CSV. Se compara
el contenido de **todas las tablas**, incluidos IDs, revisión y trazabilidad,
después de transferir, cancelar, fallar y reiniciar. Se comprueban
`integrity_check` y `foreign_key_check` tras cada verificación de conservación.

| Prueba | Resultado exigido |
|---|---|
| Caso I completo | Windows publica V1; Android revisa cuenta/fecha/V1 y descarga; conserva 48 presupuestos, 10 movimientos, enero +1.229,75 EUR, real anual +2.329,65 EUR y presupuesto +13.200,00 EUR; foto de enero completa, líquidos 9.000,00 EUR, febrero sin foto |
| Android modifica y publica | Añade un movimiento sintético de −123,45 EUR; V2 mantiene el mismo ID; Windows detiene su subida antes de abrir una sesión de transferencia y conserva su edición de −5,00 EUR |
| Cancelar, aplicar y recuperar | Cancelar la revisión no descarga bytes ni modifica tablas; confirmar instala V2, conserva respaldo previo; restaurarlo devuelve íntegramente la base Windows y exige nuevo contraste |
| Red en descarga | Error de transporte conserva base local completa; permite reintento manual |
| Descarga incompleta | La mitad de los bytes no se instala; conserva activa y permite reintento |
| Archivo inválido | Bytes no SQLite con tamaño/hash remotos coherentes son rechazados por validación de imagen; conserva activa |
| Cancelación durante transferencia | No se instala candidata; conserva cambios locales y permite reintento |
| Subida interrumpida | Remoto previo intacto y activa utilizable; último bloque incierto bloquea repetición; una nueva versión observable permite resolver mediante descarga expresa |
| Acuse perdido tras publicación | Tras reinicio se reconoce UUID/hash/versión mediante consulta; no hay segunda publicación |
| Cambios durante subida | Remoto contiene la revisión capturada; la edición posterior permanece local y pendiente |
| Carrera sin condición | Ambas operaciones superan su gate sobre V1; Android publica V2 y Windows V3; última escritura queda activa; ambas bases locales siguen íntegras; la siguiente subida Android se detiene por divergencia |

Son **9 pruebas nuevas**; red, archivo incompleto, inválido y cancelación son
cuatro variantes. El servidor asigna una sesión independiente a cada subida,
conserva bloques por sesión y usa un único ID activo. La carrera se intercala
de forma determinista después de la última comprobación y antes de publicar.
Las esperas tienen límite de 10 segundos. No hay Google ni datos personales.

Las pruebas existentes complementan esta batería: `drive_transfer_client_test`
cubre bloques, streams interrumpidos y acuses; `validated_drive_uploader_test`
cubre gates y snapshots; `drive_reconciliation_test` cubre ambigüedad;
`safe_drive_download_application_test` cubre fallo de respaldo, sustitución,
reapertura y recuperación interrumpida; `drive_screen_test` cubre los estados,
versiones y confirmaciones de la interfaz adaptable.

## Carrera del archivo único y resultado de T01

La carrera simultánea del único `autofinance.sqlite` **no está garantizada
contra sobreescritura** con el transporte actual: consultar versión antes de
escribir no equivale a una condición atómica del servidor. El historial nativo
puede purgar versiones; no se promete recuperar indefinidamente el perdedor.

T01 / MA-TSK-061 tiene el ensayo real bloqueado por OAuth: su resultado es
**indeterminado**, no una prueba de que Drive carezca de toda condición atómica.
La prueba nueva demuestra el comportamiento del cliente frente a un servidor
simulado sin condición; no resuelve esa incertidumbre empírica. Se conserva la
excepción aprobada de EP-001 §7.1 y se sigue deteniendo toda divergencia
secuencial observable. Ver [control de versiones](control-versiones-drive.md).

## Ejecución y evidencia local

Usar Flutter 3.47.0 y Dart 3.13.0 fijados, sin actualizar SDK ni lockfile:

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
flutter test --no-pub test/synchronization/drive_two_installations_test.dart
./scripts/check-quality.ps1
node docs/ep-001/verificar-casos.mjs
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
```

Los logs de esta sesión están en `.tools/069-*`, ignorados por Git. El primer
intento dentro del sandbox no pudo abrir SQLite durante la recuperación local;
la verificación se ejecutó después fuera del sandbox con temporales sintéticos
en `.tools`. No se alteró la recuperación de producción para evitar el fallo.

- Versiones y comprobación de toolchain: correctas.
- `scripts/check-quality.ps1`: formato y análisis sin incidencias; **789
  pruebas correctas**, incluidas las 9 nuevas. Los cuatro `APP_ENV` se verifican
  también por separado. Evidencia: `.tools/069-quality.log`.
- Comprobador independiente EP-001: OK, cifras obligatorias correctas.
- Builds intentados: Windows falla por `No CMAKE_CXX_COMPILER could be found`;
  Android falla por ausencia de Android SDK. No hay artefactos nativos nuevos.
- `flutter devices`: Windows y Chrome; ningún Android conectado.
- `check-google-oauth.mjs --require-configured`: bloqueo externo por proyecto
  y clientes pendientes; inventario público `blocked_external`.

## Recorrido manual real pendiente de aceptación

No se pudo ejecutar el caso I real con la misma cuenta en Windows y Android:
faltan clientes OAuth registrados, compilador C++, SDK y dispositivo Android.
No se acredita consentimiento, transferencias reales, historial Google ni
versiones visibles en dispositivos. MA-TSK-069 no cumple todavía todos sus
criterios de cierre. No sustituir esta evidencia por capturas de widgets.

Una vez disponibles esos requisitos, ejecutar con una cuenta tester y datos
sintéticos, sin reutilizar la base personal:

1. Registrar fecha, commit probado, versiones de app/OS y alias de cuenta y
   dispositivos. Ejecutar T01 y registrar su resultado real saneado; si se
   acredita condición de commit, revisar el transporte antes de aceptar.
2. En Windows importar `historico-ejemplo.csv` y crear las fichas/foto iniciales
   del caso de referencia. Verificar 48/10, enero +1.229,75, anual +2.329,65,
   presupuesto +13.200,00, líquidos 9.000, patrimonio 14.000 y colchón 3,00.
3. Pulsar Subir copia. Registrar alias del ID único, fecha y versión V1. En
   Android con la misma cuenta, revisar V1 antes de Descargar última copia;
   verificar todas las cifras anteriores y febrero «sin dato».
4. En Android añadir un real sin categoría de −123,45 EUR en enero y subir V2.
   Esperados: 11 movimientos, enero +1.106,30 y anual +2.206,20 EUR; foto,
   presupuesto y colchón sin cambios. Registrar fecha/V2 y mismo ID.
5. En Windows añadir −5,00 EUR en enero y pulsar Subir copia sobre V1: debe
   detenerse; Windows conserva enero +1.224,75 y anual +2.324,65 EUR; Drive
   conserva V2. Conservar datos locales tampoco escribe en Drive.
6. Descargar en Windows: revisar V2 y advertencia; cancelar con botón/Esc
   conserva sus cifras. Repetir y confirmar: comprobar cifras Android,
   fecha/V2 y respaldo previo en Copias locales. Restaurarlo y verificar
   cifras Windows y aviso de contraste pendiente.
7. Repetir sobre copias sintéticas con corte de red en subida/descarga,
   cancelación antes de aplicar, archivo inválido, fallo de respaldo y acuse
   incierto. Registrar mensaje, versión remota, cifras y reapertura después
   de cada fallo; nunca afirmar publicación ante respuesta incierta.
8. Modificar durante una subida y comprobar que la nueva edición sigue
   pendiente. Ejecutar la intercalación de dos subidas según T01; registrar
   ganador/historial sin prometer exclusión ni retención. En Android comprobar
   tacto/Atrás y en Windows teclado/foco de retorno.

Guardar solo evidencia saneada: alias, versiones, cifras y resultados. No
versionar tokens, identificadores privados, capturas de cuenta ni bases reales.

## Alcance de publicación

El checkout ya contenía cambios de MA-TSK-064 (subida, transferencia, estado,
factoría y README). Las pruebas nuevas los utilizan localmente, pero este
ticket solo publica su nuevo archivo de pruebas y este informe. No se incluyen
ni modifican los cambios previos. Un checkout remoto sigue dependiendo de la
publicación separada de MA-TSK-064; pasar pruebas en este árbol combinado no
acredita que esas dependencias estén publicadas.
