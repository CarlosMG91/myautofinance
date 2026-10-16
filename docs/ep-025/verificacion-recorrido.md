# MA-TSK-202 · Recorrido integrado y falsos positivos

## Alcance y aislamiento

Ticket y requisitos consultados en modo de solo lectura mediante
`GET http://localhost:4310/api/data` el 2026-10-16, tablero **My autofinance**:
MA-TSK-200 y MA-TSK-201 completados, MA-TSK-202 en curso, sin adjuntos.
Se conserva EP-001 y la interfaz aprobada de T05/EP-026. No se cambia el
estado administrativo del tablero ni se reclama aceptación visual humana.

El [guion compartido](../../test/support/diagnostic_acceptance_journey.dart)
ejecuta la composición `LocalBackupSession`, importador histórico CSV,
previsualización/confirmación EP-012, repositorios SQLite, motor de diagnóstico,
bandeja de categorización, editor patrimonial, motor EP-023 y copias/restauración
de producción. No sustituye esos servicios por proveedores falsos. Solo se
inyectan el directorio privado sintético y los bytes del CSV aprobado.

En host, cada caso crea su propio `Directory.systemTemp.createTemp`; en los
runners nativos se crea un subdirectorio `synthetic-diagnostic-acceptance/run-*`
que se elimina al finalizar. La instalación se compone con ese directorio
explícito: no abre la base activa de la persona usuaria. El CSV EP-001 viaja
comprimido como `SYNTHETIC_CSV_GZIP_BASE64`; el driver contrasta su SHA-256 con el archivo del
repositorio antes de conservar evidencias. Los ficheros originales bancarios,
OAuth y Drive no intervienen. Los casos corruptos se siembran exclusivamente
en las fixtures de memoria/temporales existentes de T02, nunca en la app.

## Criterios y pruebas

| Criterio | Evidencia ejecutable |
|---|---|
| Importar y repetir sin altas | Guion nuevo: importa el CSV EP-001 completo mediante lector y confirmador reales: 48 partidas/10 movimientos. Repite sus bytes con otro nombre y compara todas las tablas, incluida revisión, antes/después. |
| Duplicados legítimos y coincidencias | Enero inicial queda conforme con Ocio sin presupuesto y Café 54/55. Importa otro CSV sintético con un Café coincidente y un movimiento sin categoría. Hay dos avisos entre lotes y ningún error; conserva los tres UUID Café, sus importes y los ordinales originales 54/55. |
| Abrir origen y volver sin escribir | Abre el lote desde una coincidencia, retorna por la pila y compara todas las tablas. Abre la bandeja desde el pendiente y usa selector, confirmación y guardado de la función propietaria. |
| Categorizar elimina el pendiente | Tras guardar, espera el commit y recarga de la bandeja; al volver el informe está obsoleto. Repetición explícita: revisión mayor, pendiente ausente y dos avisos conservados. |
| Sin presupuesto válido | La primera revisión completa queda conforme aunque Ocio no tenga presupuesto; T02 añade el caso de base sin presupuestos, sin errores estructurales. El motivo del indicador conserva su semántica propia. |
| Ausente/parcial sin acarreo; cero válido | Selecciona febrero y comprueba foto ausente y cero valores, aunque enero esté completo. Desde diagnóstico abre el editor de febrero: principal 6.200/deuda 4.800 deja pendientes ahorro/cartera y totales nulos. Completa ahorro 0/cartera 10.500: neto 11.900 y colchón exacto 31/15 (2,07 meses). |
| Corrección del periodo e indicador | Desde Patrimonio corrige principal a 6.300 en febrero. Al volver, invalida y repite: neto 12.000 y colchón exacto 21/10 (2,10). Conserva UUID de todas las valoraciones y todos los campos de enero. |
| Recuperación invalida aun con igual revisión | Crea/restaura copia real de la base sintética corregida. El resultado pasa a obsoleto; repetir incrementa generación, conserva tablas/revisión y consulta nuevamente el indicador real 2,10. |
| Referencia inválida y conflicto presupuestario sin reparación | `sqlite_diagnostic_executor_test.dart`: «Null es pendiente; archivada conservada es válida; UUID inexistente…» y «Solape histórico raíz/nieto con cero y archivados…». Sembrado explícito en fixture; cada ejecución compara todas las tablas/revisión. |
| Cancelación y lectura fallida sin conformidad | T02: cancelación previa/durante lectura, apertura ilegible y archivo sintético ilegible sin cambiar bytes; UI T05: cancelación sin informe anterior/conformidad, regla no ejecutada y fallo de referencia con recuperación. Se reutilizan, sin duplicar pruebas suficientes. |
| Cálculos de servicios reales | Regresión T04 en [regresion-servicios.md](regresion-servicios.md), además del recorrido nuevo con proveedor/cálculo EP-023 de `local.indicators()`. «Referencia Excel» significa únicamente contrato sintético EP-001. |

Todas las ejecuciones del diagnóstico y las lecturas de evidencia comparan
**todas las tablas**, incluidas procedencias, valores originales y revisión.
Las escrituras entre diagnósticos son acciones expresas del importador,
categorización y patrimonio, o preparación de fixtures. El diagnóstico no
repara, elimina duplicados, concilia saldos ni modifica fórmulas/esquema.

## Reproducción

Usar Flutter 3.47.0, Dart 3.13.0 y JDK 17 del `toolchain.json`.
Para aislar salidas, puede asignarse `APPDATA` a un directorio nuevo dentro de
`.tools` y configurar allí `.flutter_settings` con `build-dir` y `jdk-dir`.
No modificar las preferencias globales de Flutter ni actualizar dependencias.
Las llamadas que crean bloqueos nativos de SQLite necesitan los permisos
habituales de ejecución del host, además de acceso a su directorio temporal.

```powershell
flutter --version
./scripts/check-toolchain.ps1
flutter pub get --enforce-lockfile
node docs/ep-001/verificar-casos.mjs
flutter test --no-pub --concurrency=1 test/diagnostics test/architecture_test.dart test/indicators/indicator_acceptance_test.dart test/importing/historical_csv_import_adapter_test.dart
./scripts/check-quality.ps1

./scripts/check-diagnostic-native.ps1 -Device windows
# Sustituir emulator-5554 por el dispositivo de prueba autorizado.
./scripts/check-diagnostic-native.ps1 -Device emulator-5554
flutter build windows --release --no-pub --dart-define=APP_ENV=test
flutter build apk --debug --no-pub --dart-define=APP_ENV=test
```

El driver exige los siete hitos completos y el hash correcto del CSV. Los JSON
de `recorrido-nativo` se generan únicamente tras un test nativo correcto y
contienen fecha, plataforma, revisión, generación, mes, reglas y magnitudes
leídas de los servicios reales. No son capturas HTML, goldens ni capturas de
pantalla. Los tamaños de superficie se fuerzan a 1440×1100/412×1100; la entrada
de texto se envía por el binding Flutter y el retorno por `handlePopRoute`.
No acreditan teclado físico, botón físico Android, TalkBack/Narrador ni una
aprobación visual. Las capturas nativas de interfaz T05 permanecen en
[interfaz-diagnostico.md](interfaz-diagnostico.md).
La importación y su repetición usan las API de producción con los bytes del
fixture; este guion no prueba el selector de archivos del sistema operativo.
El diagnóstico, los enlaces, la categorización y la edición patrimonial se
accionan desde sus pantallas reales.

## Resultado de la ejecución

Comprobación local del 2026-10-16:

- Flutter 3.47.0 / Dart 3.13.0, `check-toolchain.ps1` y resolución con
  `--enforce-lockfile`: correctos. `toolchain.json`, SDK y lockfile sin cambios.
  La resolución requirió acceso de red a pub.dev; las pruebas de disco se
  ejecutaron con permisos nativos del host para los bloqueos de SQLite.
- Comprobador original `node docs/ep-001/verificar-casos.mjs`: **OK**.
- Batería dirigida de reproducción: **93 pruebas correctas, cero fallos**,
  2 min 5 s. Incluye las dos pruebas nuevas en tamaños 1440/412, T01/T02/T05,
  importador histórico, aceptación real EP-023 ampliada por T04 y arquitectura.
- Recorrido **Windows nativo: correcto**, 1 min 12 s de test; siete hitos
  conservados en [windows.json](recorrido-nativo/windows.json).
- Recorrido **Android nativo: correcto**, 1 min 52 s de test; siete hitos
  conservados en [android.json](recorrido-nativo/android.json). Emulador API 37,
  proyecto compilado con SDK/Build-Tools 36 y JDK 17. El script reproducible
  `check-diagnostic-native.ps1` se ejecutó en esta plataforma.
- En ambos runners: revisión inicial 5, tras segunda importación 6,
  categorización 7, foto parcial 8, completa 9 y corregida 10. Restaurar esa
  imagen conserva revisión 10 y cambia generación de 1 a 2. El informe se
  invalida antes de repetir. Las evidencias recogen enero líquidos 900.000 /
  neto 1.400.000 céntimos, parcial sin totales, febrero completo 620.000 /
  1.190.000 y corregido 630.000 / 1.200.000; colchón 3, 31/15 y 21/10.
- SHA-256 de los bytes CSV en ambos runners:
  `0b997f5c8092369aa47a08c8cca6d4c22050abca320880a173818d4e34576b62`.

- Análisis estático completo final: **sin incidencias** (76,9 s en el
  reintento). Formato de 480 archivos sin cambios; driver comprobado también
  por separado. La resolución mantiene el lockfile; los avisos de versiones
  nuevas no se resuelven actualizando dependencias.
- Builds de la entrada principal con `APP_ENV=test`: **Windows release y APK
  debug correctos**, 60 s y 28,3 s respectivamente. Windows usa Visual Studio
  2026 Insiders instalado; no acredita VS 2022. Android usa Temurin JDK
  17.0.20.1 y SDK/Build-Tools 36. No hay firma de distribución. Los logs
  locales `ma-tsk-202-build-windows.log` y `ma-tsk-202-build-android.log`
  corresponden a la entrada principal, después de los recorridos nativos.

- `scripts/check-quality.ps1` del reintento: **no queda verde**. Formato y
  análisis correctos; batería general terminada en 13 min 23 s con **1.961
  pruebas correctas y tres fallos**. Los dos tamaños del nuevo recorrido de
  aceptación y las pruebas de diagnóstico pasan también en esta batería.
  Los fallos son:
  - `test/drilldowns/report_drilldown_journey_test.dart`, Windows:
    `Bad state: No element` al buscar la celda de real de Estado,
    `test/support/report_drilldown_journey.dart:171`.
  - `test/movements/pending_lifecycle_test.dart`, Windows y Android:
    `Bad state: No element` en
    `test/support/pending_lifecycle_journey.dart:144`. Son los fallos previos
    documentados por [T04](regresion-servicios.md) y
    [T05](interfaz-diagnostico.md).
  Ninguno de esos cuatro archivos cambia en MA-TSK-202. No se declara
  conformidad global ni se modifica el alcance de otras épicas para ocultarlos.
- Repetición aislada secuencial de
  `test/drilldowns/report_drilldown_journey_test.dart`: **dos pruebas
  correctas**, 1 min 07 s. El fallo de desgloses no se reproduce aislado;
  no se atribuye una causa definitiva ni se convierte la pasada general en
  correcta. Los dos fallos EP-015 coinciden con la reproducción aislada
  conservada por T04; no se duplican nuevamente esas pruebas suficientes.
- Variantes de arranque verificadas por separado porque el fallo general
  detiene el script antes de ellas: `development`, `test`, `production` e
  `invalid-synthetic`, **una prueba correcta por variante**.

La evidencia del reintento queda en los logs locales ignorados
`ma-tsk-202-retry-quality.log`, `ma-tsk-202-retry-drilldown.log` y
`ma-tsk-202-retry-environment-*.log`. El resultado de calidad global permanece
fallido; no hay criterios del recorrido de diagnóstico pendientes de ejecución.

Las pruebas y builds se ejecutan sobre el checkout con los cambios
concurrentes de sincronización encontrados al comenzar. Estos cambios, README
y prototipos ajenos se excluyen de la entrega de MA-TSK-202. No se interpreta
la cobertura del diagnóstico como conformidad de la batería general.

Los primeros intentos nativos detectaron límites de comandos Windows al
transportar el CSV sin comprimir y conflicto entre `ANDROID_SDK_HOME` y
`ANDROID_USER_HOME`. Se resolvieron comprimiendo únicamente el transporte del
fixture y usando una única ruta Android, sin modificar SDK ni preferencias
globales. No son criterios pendientes después de las repeticiones correctas.
Los logs y binarios permanecen ignorados en `.tools`/`build`; solo se guardan
el guion, driver, script, pruebas y evidencia sintética JSON.

Se incluyen exclusivamente los ocho archivos propios de MA-TSK-202 en la rama
configurada `ticket/ma-tsk-193`. El remoto consultado coincide con el punto de
partida `d4414cd`; no se fuerza la subida ni se cambia el estado administrativo
del tablero. No se atribuye aceptación visual humana a esta verificación.
