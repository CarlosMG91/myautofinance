# MA-TSK-254 · Exportación y consulta independiente

Revisión del **2026-10-20**. **T08 bloqueado, sin completar sus criterios de
instalaciones finales.** Se ha repetido la lectura independiente de los archivos
sintéticos conservados de MA-TSK-226. No se ha exportado desde paquetes finales,
ni transferido un documento desde un teléfono físico en esta ejecución.

Se consultó `GET http://localhost:4310/api/data`: tablero **My autofinance**,
workspace coincidente, MA-TSK-254 en curso y requisito MA-TSK-248 completado.
Se leyeron sus criterios y las dependencias EP-027/028/029. Los estados `done`
de 226/235/245 se contrastaron con sus evidencias; no acreditan por sí mismos
los paquetes finales. No se cambian estados del tablero ni otros tickets.

Fuente inicial: `cec01ec34920644dd27a1f752bf2610e1d4b7f7d`, rama configurada
`ticket/ma-tsk-193`, seguimiento `origin/ticket/ma-tsk-193`. Hay cambios
concurrentes de sincronización, README y archivos sin seguimiento: quedan fuera
del alcance y del commit de este ticket. No se ha reproducido un fallo de
integración del producto que justifique modificar exportadores, UI o esquema.

## Qué se ha comprobado ahora

La [evidencia estructurada](evidencia-portabilidad.json) registra hashes de los
16 ZIP y sus manifiestos/SQLite, identidad y revisión, herramientas y resultados.
El origen sigue siendo el de [MA-TSK-226](../ep-027/verificacion-portabilidad.md):
runner Windows debug con IFileSaveDialog, emulador Android API 37 con Downloads
SAF y transferencia histórica de documentos públicos mediante ADB pull. Esos
archivos ya estaban en Windows; releerlos no repite su guardado ni transferencia.

Se reutilizó sin cambios `scripts/verify-export-portability.py`: lector de la
biblioteca estándar Python, sin importar Flutter ni servicios de Autofinance.
Validó inventarios, CRC, tamaños, SHA-256, diccionario exacto, columnas y filas
contra las capturas nativas conservadas `windows.json` y `android.json` de 226.
Los 16 hashes de ZIP coinciden con la evidencia publicada de 226.

| Caso reutilizado, en ambas plataformas | Resultado de lectura actual |
|---|---|
| `all.zip`, revisión base 19 | 10 reales, 48 partidas; real anual +232965 y presupuesto +1320000 céntimos. |
| `january.zip`, revisión 19 | 6 reales y 4 partidas; +122975 y +110000 céntimos. Selección por fecha de valor y mes, contexto completo. |
| `empty.zip`, diciembre 2025 | Cero filas en los cuatro CSV financieros; cabeceras presentes. Los tres catálogos conservan 4 cuentas, 10 categorías y 3 periodos de liquidez. |
| `base-copy.zip`, revisión 19 | SQLite completa, 12 tablas; identidad/revisión y conteos coinciden con manifiesto y captura. Enero líquidos 900000/neto 1400000 céntimos; febrero sin foto. |
| `partial.zip` / `zero.zip` | Febrero parcial conserva pendientes; al completar, ahorro cero explícito, líquidos 620000/neto 1190000 céntimos. |
| `history.zip` | Cartera líquida desde febrero: enero líquidos 900000, febrero 1670000; neto febrero 1190000 céntimos. |
| `variant-copy.zip`, revisión 24 | SQLite completa con originales, Discrecionalidad, Unicode, separadores, saltos y extremo int64 preservados; no se usan sus totales como caso base T02. |

Se contrastaron los oráculos base de [T02](oraculos.json) con los CSV de ambas
plataformas usando enteros, incluyendo dos Café con UUID distintos y suma −2000
céntimos. Los presupuestos exportados conservan el signo interno de la app:
no se reimportan por el contrato histórico de signo inverso. Las copias completas
no tienen filtro de meses; los rangos CSV no recortan cuentas/categorías/liquidez.
Los originales persistidos se contrastan según el diccionario EP-027, sin
atribuir al CSV la totalidad del contexto que conserva la SQLite completa.

Las cuatro SQLite se extrajeron a carpetas nuevas y se abrieron en solo lectura:
integridad `ok`, sin errores de claves externas, application_id/user_version,
datasetId/revision, todas las filas de las 12 tablas y hashes finales correctos,
sin sidecars. Las 13 sentencias SQL de la guía se ejecutan en cada una. En las
dos copias extremas, una agregación da `integer overflow`, límite ya documentado
en 226 y en la guía; el verificador lo registra y suma los enteros con Python
(total exacto `9223372036854706772` céntimos). No se cuenta esa agregación como
consulta satisfactoria ni se convierte a REAL.

Además, para **cada copia base**, se ejecutó
`scripts/check-export-recovery-guide.ps1`, que toma literalmente el bloque de
validación/extracción de [la guía EP-027](../ep-027/recuperacion-sqlite.md),
cambiando únicamente las dos rutas. Ambas pasaron con `sqlite3 -readonly`:
integridad, referencias, esquema, identidad/revisión, conteos y consultas;
ZIP original y base extraída conservaron sus hashes. Los destinos nuevos están
en `.tools/ma-tsk-254/Consulta nueva <plataforma>-<uuid>`, fuera de la instalación.
No se abre ni sustituye ninguna base activa y no se reconstruye desde CSV.

Los negativos del verificador ejecutaron también el script de la guía: ZIP
truncado, hash del manifiesto falso, revisión incompatible, formatVersion 2 y
destino ya existente se rechazaron con salida distinta de cero. El original y
el archivo testigo del destino previo permanecieron intactos. Son mutaciones
temporales de copias sintéticas, sin alterar los ZIP conservados.

## Bloqueos de los criterios finales

| Criterio T08 | Estado y continuación concreta |
|---|---|
| Guardar CSV todo/enero/rango vacío y copia completa desde Windows final mediante destino del sistema | **Bloqueado P01**: no se localizó candidato final ni perfil de ensayo identificado. EP-028 MA-TSK-233/235 debe aportar paquete, manifiestos/hash y evidencia de instalación. `dist-private/windows` contiene compiler-probe y fixtures synthetic, no evidencia de ese candidato. Ver [T04](verificacion-windows.md). |
| Mismo recorrido desde Android final | **Bloqueado P02**: `dist-private/android` contiene ci-fixture y signing-check; falta candidato final con manifiesto y teléfono físico de ensayo. ADB solo enumera `emulator-5554`, `sdk_gphone64_x86_64`. EP-029 MA-TSK-245 conserva límites de entrega; ver [T05](verificacion-android.md). |
| Transferencia normal Android físico → carpeta nueva Windows | **Bloqueado P02**: no se ejecutó. Usar documento público guardado por SAF y un medio accesible al usuario, por ejemplo USB/MTP, conservando original y hash de recepción. No usar root, run-as ni leer la base privada. |
| Guía independiente sobre copias de esos paquetes | **Bloqueado P01/P02**: la guía pasó ahora sobre los archivos de 226, pero falta repetirla sobre los nuevos ZIP finales y capturar sus resultados y revisión. |

Se solicitaron al usuario las rutas privadas de candidatos/manifiestos y los
entornos aislados de ensayo. No se proporcionaron en el ticket ni se localizaron
en las rutas examinadas. No se inspeccionan perfiles financieros personales ni
se instala sobre ellos. OAuth no es un requisito de la exportación local; no se
añade como dependencia de T08. Tampoco se introduce otra herramienta de
restauración, formato, exportador, interfaz o motor financiero.

Al disponer de ambos candidatos, registrar por instalación paquete/hash/commit,
versión, entorno production, plataforma física, proveedor y destino devuelto,
fecha, datasetId/revision y estado T02 antes de exportar. Guardar los cuatro ZIP
base citados, conservar las exportaciones previas y registrar hashes y conteos
observados. Si la revisión difiere, contrastar la captura de esa revisión en vez
de asignarle cifras de otra. Transferir el ZIP Android por el medio acordado y
seguir la guía en sendas carpetas nuevas. Reutilizar las variantes de 226 que
siguen acreditadas; repetir solo las afectadas si aparece una regresión.

## Comandos y verificación

Herramientas usadas: Flutter 3.47.0 / Dart 3.13.0, Python 3.14.2 (sqlite3
integrada 3.50.4), CLI SQLite 3.54.1, PowerShell de Windows. Se mantuvieron
toolchain y lockfile. Logs y ZIP sintéticos quedan ignorados en `.tools/`;
solo se versionan este informe y la evidencia JSON sin binarios ni secretos.

```powershell
node docs/ep-001/verificar-casos.mjs
node docs/ep-030/preparar-datos.mjs
python scripts/verify-export-portability.py --root .tools/226-public --evidence .tools/226-evidence --output .tools/ma-tsk-254/independent.json --sqlite-cli .tools/226-sqlite/sqlite3.exe
# Ejecutar una vez por plataforma, con destino nuevo e inexistente:
./scripts/check-export-recovery-guide.ps1 -Zip .tools/226-public/windows/base-copy.zip -Destination '<carpeta nueva>' -Sqlite '<sqlite3.exe>'
flutter test --no-pub --concurrency=1 --reporter expanded test/synchronization/data_export_test.dart test/synchronization/portable_backup_export_test.dart test/synchronization/native_export_saver_test.dart test/synchronization/export_controller_test.dart test/synchronization/export_screen_test.dart test/integral_reference_test.dart
./scripts/check-quality.ps1
```

El alias Python de Windows no era ejecutable en sandbox; se usó el intérprete
instalado `AppData/Local/Python/pythoncore-3.14-64/python.exe`. La enumeración
ADB restringida falló al crear `\\.android`; su repetición autorizada solo leyó
la lista de dispositivos. Las pruebas dirigidas restringidas dieron 28 correctas
y 29 fallidas con bloqueo de recuperación SQLite temporal. Calidad restringida
se detuvo en pub.dev (`SocketException 10057`). Se repitieron ambas fuera del
sandbox; resultados finales en la evidencia y el apartado siguiente.

Las **57 pruebas dirigidas pasaron** en la repetición autorizada: 48 de
exportación/guardado/controlador/pantalla y 9 de T02 con SQLite temporal real.
Los destinos del test de adaptador usan MethodChannel simulado; no acreditan
el selector del paquete final. La resolución con `--enforce-lockfile` pasó
fuera del sandbox, formato comprobó 508 archivos sin cambios y el análisis
completo terminó sin incidencias. No se compilan plataformas porque solo se
añade evidencia documental; un build de ensayo no resolvería P01/P02.

La batería general terminó con **2026 correctos y 3 fallidos**; calidad global
**no aprobada**. Dos fallos pertenecen a
`test/synchronization/local_recovery_journey_test.dart` (restauración/reinicio
EP-001 y rollback por fallo de disco): archivo temporal ocupado (errno 32),
contraste de filas y conexión Drift cerrada. Se comparan con los fallos de ese
archivo ya publicados en [226](../ep-027/verificacion-portabilidad.md), sin
afirmar que la causa esté resuelta. Propietario EP-006; coordinación T01/T07 de
EP-030. El tercero es `test/wealth/wealth_photo_screen_test.dart:295`, ausencia
del texto esperado `Pendientes: Z Deuda sintética` después de guardar: propietario
EP-017, coordinación EP-026/030. No es una discrepancia de los CSV/SQLite
exportados. No se modifican esos tests ni sus motores para ocultar los fallos.

Repetición secuencial de ambos archivos: **22 correctos / 1 fallido**.
Recuperación pasa **8/8**; la misma aserción de fotos vuelve a fallar. Se deriva
su contraste de expectativa/UI al propietario, sin atribuir pérdida de datos ni
diagnosticar su causa solo por el texto ausente. Los cuatro arranques
development/test/production/invalid-synthetic pasan **4/4**, ejecutados después
porque el script general se detuvo en la suite. No se repite la batería completa
ni se declara verde. Logs en `.tools/ma-tsk-254/quality-authorized.log`,
`targeted-authorized.log`, `recovery-photo-repeat.log`, `guide-*.log`,
`independent.json` y `bootstrap-*.log`; sus hashes quedan en la evidencia.

La revisión de enlaces locales, JSON y whitespace de los dos archivos del
ticket es correcta. T08 permanece bloqueado por P01/P02 y EP-030 conserva su
requisito de expediente y aprobación humana explícita.
