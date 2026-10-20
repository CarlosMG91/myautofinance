# T02 · Datos y oráculos comunes · MA-TSK-248

Preparación de EP-030 independiente de paquetes, dispositivos y OAuth. Fuente:
ticket facilitado por el usuario y contrato aprobado EP-001; no se ha actualizado
el tablero desde este trabajo. No acredita entrega ni aceptación de EP-030.

Se reutilizan [CSV original](../ep-001/historico-ejemplo.csv),
[casos A–I y variantes D/G/H/J](../ep-001/casos-referencia.md),
[contrato CSV](../ep-001/contrato-csv.md), los repositorios SQLite y los soportes
de copias existentes. No hay cambios en producto, esquema, toolchain o UI EP-026.
Los importes del [oráculo estructurado](oraculos.json) son **céntimos EUR**;
`null` significa sin dato, nunca cero. Los resultados derivan de EP-001;
el manifiesto organiza su reproducción, no aprueba reglas nuevas.

## Preparar archivos y caso base

Desde la raíz, con Node y las versiones de `toolchain.json`:

```powershell
node docs/ep-001/verificar-casos.mjs
node docs/ep-030/preparar-datos.mjs
node docs/ep-030/preparar-datos.mjs --destino "$env:TEMP\autofinance-T02-ensayo-01"
flutter test --no-pub test/integral_reference_test.dart
```

El destino debe ser nuevo, con padre existente. Si ya existe, se rechaza sin
sobrescribir. El generador solo escribe cuatro CSV UTF-8/LF y `oraculos.json`;
no accede a instalaciones, SQLite ni Google. `base.csv` conserva todos los
campos del original; normaliza únicamente CRLF a LF si el checkout los introduce.
Los SHA-256 de los **bytes transportados** están en `files` del oráculo.
Se contrasta también con la copia portable existente
`test/support/budget_proposal_reference_csv.dart`. Copiar estos mismos archivos
a ambos equipos; comprobar `Get-FileHash -Algorithm SHA256` en PC antes del envío
y los hashes de las entradas efectivamente usadas en la evidencia de cada runner.
Un archivo renombrado con los mismos bytes conserva su hash.

Antes de importar, usar exclusivamente una instalación/perfil de ensayo sin
datos financieros personales. Registrar el directorio o perfil aislado,
plataforma, versión, hash del paquete y modalidad: host, runner nativo, emulador
o dispositivo físico. Si no puede acreditarse el aislamiento, no ejecutar allí.
No limpiar ni sustituir una instalación personal para crear el ensayo.

En la UI vigente importar `base.csv`, revisar y resolver `Cuenta principal`
(cuenta líquida vigente desde enero 2026), las cinco raíces y sus descendientes.
Marcar solo `Ingresos` como ingreso; crear las rutas exactas del CSV, hasta
`Alimentación / Supermercado / Compra semanal`. Confirmar 48 partidas y 10 reales.
Crear las fichas restantes y guardar esta foto manual del **2026-01-01**:

| Ficha | Tipo | Liquidez | EUR |
|---|---|---|---:|
| Cuenta principal | Cuenta | Líquida | 6000,00 |
| Cuenta de ahorro | Cuenta | Líquida | 3000,00 |
| Cartera | Cartera | Media | 10000,00 |
| Deuda familiar | Deuda | No aplica | 5000,00 |

Todas vigentes desde enero 2026. Febrero queda sin foto. No calcular saldos
desde movimientos ni generar automáticamente la otra pierna del ahorro.
Conservar **dos Café** idénticos con UUID distintos y Discrecionalidad original.
La repetición del mismo CSV, incluso renombrado, da cero altas.

| Consulta base | Resultado EUR salvo indicación |
|---|---:|
| Enero real / presupuesto / diferencia | +1229,75 / +1100,00 / +129,75 |
| Febrero real / presupuesto / diferencia | +1099,90 / +1100,00 / −0,10 |
| 2026 real / presupuesto | +2329,65 / +13200,00 |
| Enero líquidos / activos / deuda / neto | 9000,00 / 19000,00 / 5000,00 / 14000,00 |
| Enero ingresos anuales previstos / promedio mensual | 36000,00 / 3000,00 |
| Enero indicador | 3,00 meses |
| Febrero patrimonio / indicador | sin dato / `foto_ausente` |

El detalle por raíz y mes de las cinco vistas permanece en los casos B–G de
EP-001. Ocio enero tiene dos Café (−20,00) sin presupuesto; los padres agregan
las hojas una vez. Patrimonio no tiene suma anual. Diagnóstico debe poder
recalcularse sin escrituras: prueba existente `test/diagnostics/`.

## Separación y reposición de variantes

Guardar una copia manual local validada **BASE-T02** y una exportación SQLite
portable con los servicios existentes de EP-006/027. Conservarlas fuera del
repositorio, junto con hash, identidad y revisión. Antes de **cada** variante,
restaurar BASE-T02 mediante el flujo seguro de copias locales y verificar las
cifras base; nunca aplicar variantes en cadena salvo el predecesor expresamente
indicado. Conservar también el respaldo previo automático recuperable. No copiar
archivos SQLite encima de una base activa ni transportar WAL/SHM.

En pruebas automatizadas, `test/support/integral_reference.dart` recibe una base
vacía desechable del llamador y utiliza el lector CSV, preview/confirmación,
repositorios y fotos reales. Reutiliza el CSV portable ya existente; no es un
servicio de siembra del producto. Cada test crea su propio directorio temporal;
la única secuencia intencionada es V03→V04→V05→V06. No invocarlo sobre una
instalación existente. La reposición humana siempre utiliza la copia preservada.

| ID | Inicio y operación | Resultado esperado / referencia |
|---|---|---|
| V01 | BASE; importar `categoria-pendiente.csv` sin categoría | 12 reales, 48 partidas; Sin clasificar +4,00 (dos filas +7/−3), enero +1233,75 y diferencia +133,75. No asignar ingreso por signo. EP-001 J. |
| V02 | BASE; revisar `cuenta-sin-resolver.csv` sin vincular esa cuenta | Confirmación bloqueada; 10/48 y revisión intacta. Cancelar sin altas. Una cuenta pendiente pertenece a la revisión; no se persiste un real sin cuenta. |
| V03 | BASE; consultar febrero | `foto_ausente`, sin patrimonio ni indicador. No arrastrar enero. |
| V04 | BASE; febrero principal 6200 y deuda 4800 | `foto_incompleta`; pendientes ahorro/cartera, totales sin dato. |
| V05 | V04; completar ahorro 0 y cartera 10500 | Líquidos 6200, activos 16700, deuda 4800, neto 11900, indicador 2,07 meses. El cero es dato. |
| V06 | V05; cartera líquida desde febrero | Enero 9000 y 3,00 meses; febrero 16700 y 5,57 meses; neto febrero 11900. Periodos sin huecos ni solapes. Corrección histórica de vuelta a media recupera 6200 y 2,07. EP-001 D. |
| V07 | BASE; revisar `padre-incompatible.csv`, resolver Vivienda existente | Rechazo por padre/descendiente en enero; 48 partidas, +1100 enero y revisión intactos. El CSV de entrada trae +1000, se normaliza a −1000. EP-001 A/H. |
| V08 | BASE; calcular propuesta 2027 desde reales 2026 sin guardar | 60 asignaciones en raíces. Enero: +3100/−1000/−360/−500/−20; febrero: +3020/−1000/−430/−500/0, orden Ingresos/Vivienda/Alimentación/Ahorro/Ocio. Marzo–diciembre: cero editable por raíz. Redondeo a decena por mes equivalente, no promedio anual. Cancelar conserva 2026 y deja 2027 sin partidas. Edición/guardado/desglose: EP-001 H y recorrido EP-018 existente. |
| V09 | BASE; marzo/diciembre 2026 y cambio a enero 2027 antes de guardar V08 | Marzo/diciembre real cero, presupuesto +1100; enero 2027 sin reales ni partidas, no presupuesto cero explícito. Sin foto → `foto_ausente`; no heredar filtros/foto ni presupuesto de 2026. Navegación histórica adicional: soporte MA-TSK-146. |
| V10 | BASE; eliminar salario solo marzo | `ingresos_incompletos`, pendiente marzo aunque enero tenga ingreso. |
| V11 | BASE; salario explícito cero en los doce meses | `ingresos_nulos`, no incompleto. |
| V12 | BASE; ambas cuentas líquidas enero a cero | Líquidos 0, neto 5000, indicador 0,00 meses válido. |

V01 es la combinación de las dos filas pendientes aprobadas en J, sin añadir
las otras cuatro operaciones de J; el delta neto es +4,00. Los CSV V02/V07 son
entradas auxiliares para ejercer restricciones aprobadas, no nuevos bancos.
Para una categoría nombrada pero aún no resuelta, revisar BASE en una instalación
vacía antes de asignar el árbol: la revisión no permite confirmar hasta resolver
sus referencias. Distinguirlo del real persistido de V01 con categoría NULL válida.

## Comparación entre Windows y Android

Dos importaciones independientes producen UUID/revisión propios: comparar sus
cifras y relaciones por ruta no demuestra portabilidad. Para PC→Android preparar
BASE una sola vez, preservarla, subir manualmente y descargar por el flujo Drive
existente. Tras la descarga deben coincidir datasetId, revisión y **todas las filas
financieras y de trazabilidad**: las doce tablas del manifiesto EP-027, incluidos
UUID, categoría, cuenta, fecha, signo, import_rows/originales, fotos e historial de
liquidez. La prueba T02 contrasta una copia consistente con lector SQLite
independiente, todas las tablas y `ORDER BY rowid`; para archivos producidos por
distintas herramientas ordenar por claves primarias según esquema antes de comparar.

Exportar copias portables separadas, validar manifiesto, hashes, `integrity_check`
y `foreign_key_check` siguiendo [guía EP-027](../ep-027/recuperacion-sqlite.md).
Conservar originales; consultar solo extracciones nuevas. La consulta SQL
independiente valida datos sin app. Reutilizar el verificador
`scripts/verify-export-portability.py` y su contrato de evidencia de EP-027,
sin tomar su dataset distinto como BASE-T02.

No comparar como igualdad tokens, sesión, instalación/Keystore/Credential Manager,
rutas, catálogo local de copias, exportId/createdAt del ZIP ni estado Drive por
instalación. El hash del ZIP puede diferir por esos metadatos; comprobar el hash
interno de cada imagen y comparar sus tablas/identidad/revisión. Una edición en
Android crea una revisión nueva esperada: registrar antes/después y cotejar solo
después de que Windows descargue esa misma versión.

## Fallos por puntos de prueba existentes

Ejecutar en clones de BASE; no dañar la única copia recuperable. Los dobles y
errores se inyectan **solo en tests**, nunca mediante un interruptor del paquete
final. Registrar proveedor y modalidad en cada evidencia.

| Caso | Soporte existente | Oráculo |
|---|---|---|
| F01 Divergencia observable, dos instalaciones y carrera | `test/synchronization/drive_two_installations_test.dart`, `drive_reconciliation_test.dart` | Divergencia previa impide subida; ambas imágenes conservadas, sin fusión. Excepción aprobada: dos consultas de una versión pueden terminar con última escritura ganadora; no exigir CAS. |
| F02 Corte/acuse ambiguo/incompleto | `drive_transfer_client_test.dart`, `installation_sync_state_test.dart` | No anunciar éxito incierto, volver a consultar al reintentar; remoto anterior utilizable hasta publicación completa. |
| F03 Descarga inválida, cancelación y respaldo fallido | `validated_drive_downloader_test.dart`, `safe_drive_download_application_test.dart`, `local_restore_candidate_test.dart` | No sustituir local; cancelar no escribe. Tras confirmación y éxito, copia previa recuperable e identidad/revisión descargadas. |
| F04 Disco lleno, intercambio y proceso interrumpido | `local_recovery_journey_test.dart`, `test/support/restore_crash_worker.dart` y `backup_lock_process.dart` | Todas las tablas, identidad, revisión y trazabilidad anteriores o imagen validada según fase; recuperación idempotente, sin pérdida. |
| F05 Lote o edición fallida | `test/movements/movement_batch_test.dart`, `test/importing/csv_import_flow_test.dart` | Cancelación y fallo revierten el lote; sin confirmación parcial ni pérdida de Café. |

Son proveedor HTTP/Drive simulado y SQLite temporal del host. No acreditan fallos
de Google ni dispositivo físico. MA-TSK-253 reutiliza estos puntos y añade la
evidencia remota real después de datos/OAuth Windows. Los fallos de producto que
aparezcan se reproducen antes de corregir; carencias funcionales se derivan al
propietario indicado en [matriz T01](auditoria-cobertura.md), sin ampliar UI aquí.

Las suites históricas crean sus propios fixtures sintéticos; en particular
`recovery_reference.dart` reproduce cifras A–G, pero no conserva todos los
conceptos, fechas y campos originales del CSV. No tratar sus bases como una
imagen BASE-T02 ni comparar sus UUID con los de una importación independiente.
En cada escenario guardar la instantánea completa del fixture que efectivamente
usa y contrastar contra ella. El soporte T02 usa el CSV exacto para preparar
las futuras ejecuciones comunes y evita trasladar esas diferencias al caso base.

## Enlace Openbank

Se ha leído el registro local `docs/ep-014/fixtures/MA-TSK-129-bloqueo.md`:
no contiene un fixture bancario; declara que muestra, estructura y resultados
siguen sin determinar. Es un archivo concurrente ajeno que no se incorpora al
commit T02. La evidencia versionada de
[MA-TSK-131](../ep-014/verificacion-reapertura-131.md) mantiene ese límite.
`oraculos.json.openbank.fixtures` queda vacío expresamente.

Cuando MA-TSK-129 entregue fixtures fieles, enlazar su revisión Git, ruta y SHA-256
de bytes, evidencia de fidelidad a MA-TSK-124, formato/contenedor/hojas/cabeceras,
ordinals y originales, importes normalizados, cuentas/categorías por resolver,
conteos/sumas por periodo, repetición cero, solapamiento revisable, error y
cancelación sin lote parcial. Usar sus salidas aprobadas sin inventar resultados.
Verificar además que las fotos manuales base no cambian al importar. Si cambia
el contrato, devolver a EP-014 antes de ejecutar el recorrido final.

La preparación común T02 puede entregarse con este enlace pendiente; Openbank
final en MA-TSK-250/251/255 sigue **bloqueado** hasta entrega efectiva. Ningún CSV
de este paquete, JSON sintético anterior ni archivo con extensión XLS supuesto
sustituye esa caracterización.
