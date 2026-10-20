# MA-TSK-250 · Recorrido financiero en Windows instalado

Revisión del **2026-10-20**. **T04 bloqueado; no completado ni aceptado.**
Se corrige una regresión del guion de integración y se prepara el recorrido
del candidato instalado. Las pruebas de host no acreditan ese recorrido.

## Identidad comprobada y límites

- Epic Board consultado por `GET http://localhost:4310/api/data`: tablero
  **My autofinance**, workspace coincidente, MA-TSK-250 en curso y requisito
  MA-TSK-248 completado. Leídos sus criterios y los de MA-TSK-235/249. Consulta
  de solo lectura; no se cambia el estado de tickets ni se crean derivaciones.
- Fuente inicial: `4c9cb51c8f2a46c6c99b80f8872b91e1b6053fe7`, rama configurada
  `ticket/ma-tsk-193`, remoto `origin`. Versión fuente **0.1.0+1**, Flutter
  **3.47.0**, Dart **3.13.0**. Esta identidad es del código, no de un instalador.
- Host Windows x64: registro `DisplayVersion=26H2`, build **26300.9711**.
  No se deduce cobertura Windows 10/11 limpio a partir de esta observación.
- Control nativo `@oai/sky.list_apps`: Autofinance no aparece. No hay registro
  Autofinance en las claves Uninstall HKCU/HKLM consultadas ni EXE en el destino
  contractual `%LOCALAPPDATA%/Programs/Autofinance/myautofinance.exe`.
  Esto no descarta una entrega externa cuya ruta no se haya proporcionado.
- `dist-private/windows` contiene carpetas `synthetic-*` y `compiler-probe`;
  no hay carpeta de entrega `installer-*`/`payload-*`. Los EXE de esas pruebas
  no se ejecutan ni se identifican como paquete final. No se ha recibido un
  adjunto/ruta de candidato externo ni un perfil Windows de ensayo acreditado.
- **Paquete/EXE instalado, APP_ENV embebido, versión instalada, commit del
  binario, SHA-256 de Setup/EXE y perfil de ensayo: sin acreditar.** No se
  asigna al runner existente la identidad de una instalación production.
- Se preservan README, fuentes Drive, prototipos y fixtures ajenos presentes
  al inicio. La calidad local incluye ese overlay concurrente; no demuestra
  que un checkout limpio de HEAD pueda generar una entrega final.

No se abren bases, credenciales o sesiones financieras personales, no se
instala ni desinstala software y no se opera sobre Drive. No hay capturas de
una app instalada en esta ejecución; no se reutilizan imágenes HTML, goldens
ni capturas de runner como evidencia de ella.

## Bloqueos y propietarios

| ID | Comprobación actual | Continuación necesaria |
|---|---|---|
| W01 | Sin candidato production identificable ni perfil aislado utilizable. [MA-TSK-235](../ep-028/verificacion-e2e.md) declara expresamente que no ejecutó el instalador final, pese al estado done del tablero. | EP-028 MA-TSK-233/235: entregar candidato de la [generación existente](../ep-028/generacion-privada.md), manifiestos/hashes y evidencia efectiva de instalación. Aportar usuario/perfil desechable sin datos personales. |
| W02 | `node scripts/check-google-oauth.mjs --require-configured` devuelve 1: proyecto y clientes pendientes. `vswhere -version [17,18)` no devuelve instalación VS2022. | EP-030 MA-TSK-249 y EP-028: resolver configuración real y toolchain de producción si es necesario generar el candidato. El [informe OAuth](oauth-windows.md) tampoco acredita sesión real por figurar done. No cambiar IDs, versiones o gates para fabricar un paquete. |
| W03 | Openbank sigue deshabilitado en `AppRouter`; [MA-TSK-131](../ep-014/verificacion-reapertura-131.md) no acredita lector/muestra. El registro local concurrente `docs/ep-014/fixtures/MA-TSK-129-bloqueo.md`, leído sin incorporarlo a este commit, declara ausencia de fixtures caracterizados. `oraculos.json.openbank.fixtures` está vacío. | EP-014 MA-TSK-124/129/131: caracterización, fixtures fieles y lector/integración efectivos. No se ha leído una muestra bancaria ni se sustituye por CSV o adaptador sintético. |

Las derivaciones anteriores documentan propietarios existentes, sin ampliar
alcance ni introducir interacciones nuevas. W01 bloquea todos los resultados
de aplicación instalada de la matriz inferior; W03 bloquea además Openbank.
Una instalación externa disponible permitiría revisar W01 sin reconstruirla;
W02 es una barrera del generador actual, no una prueba de fallo financiero.

## Corrección de integración I01

Se reproduce el fallo de T01/T02 en las dos variantes de
`test/movements/pending_lifecycle_test.dart`: `Bad state: No element` al buscar
`PopupMenuButton<String>` en Real anual. EP-026 ya ofrece Gestión en la barra
Windows y Más → Gestión en Android. El error sucede antes de categorizar;
no demuestra pérdida de datos ni defecto del motor financiero.

Se modifica únicamente `test/support/pending_lifecycle_journey.dart` para
recorrer esas entradas públicas y retornar por sus pantallas intermedias a
Real anual con la ruta/periodo originales. Se conservan las aserciones de
cancelación, asignación individual y por lote, selección/filtros, conteos,
historial/originales, UUID, revisión, fotos/presupuesto intactos, duplicados,
reimportación con nombre distinto y persistencia tras cerrar/reabrir SQLite.
No se elimina el caso, no se salta a la bandeja para eludir la navegación y
no se modifica UI, esquema, motor, importador o servicio de producto.

No se recompilan plataformas: cambian un soporte de pruebas y este informe,
sin modificar la aplicación ni sus adaptadores nativos. Construir un runner
APP_ENV=test no resolvería la ausencia del candidato instalado de W01.

El soporte también lo consume `integration_test/pending_categorization_test.dart`;
su adaptación se verifica aquí con widgets de host. No se ha ejecutado ese
runner nativo en esta sesión, ni representa un EXE instalado.

## Comprobaciones de esta ejecución

| Control | Resultado observado |
|---|---|
| `flutter --version`; `scripts/check-toolchain.ps1` | Versiones fijadas correctas. |
| `node docs/ep-001/verificar-casos.mjs` | OK: 48 partidas/10 reales, enero +1229,75, anual real +2329,65 y presupuesto +13200,00 EUR; casos de liquidez incluidos. |
| `node docs/ep-030/preparar-datos.mjs` | OK: CSV original/copia portable, dos Café y hashes de las cuatro entradas T02. |
| Regresión antes de corregir, con acceso temporal autorizado | **0 correctas / 2 fallidas**, ambas en la búsqueda del menú retirado. |
| Misma regresión después de corregir | **2/2 correctas**, 48 s; Windows tabla y Android tarjetas en host Windows, SQLite temporal real y adaptador de importación sintético EP-012. |
| `scripts/check-quality.ps1` sobre la corrección | Lockfile resuelto, formato de 508 archivos sin cambios y análisis sin incidencias. Suite general: **2019 correctas / 4 fallidas**, 15 min 36 s; salida 1. I01 ya no falla. Calidad global **no aprobada**. |
| Comprobación secuencial de los archivos fallidos | **12/12 correctas**, 5 min 26 s, con `flutter test --no-pub --concurrency=1 test/budget/budget_lifecycle_test.dart test/synchronization/local_recovery_journey_test.dart test/wealth/wealth_lifecycle_test.dart`. No sustituye el resultado general. |
| Variantes de arranque development/test/production/invalid-synthetic | **4/4 correctas**, ejecutadas secuencialmente con `test/environment_bootstrap_test.dart` después de la suite general. Son tests de host, no prueba del APP_ENV de un binario instalado. |

Fallos de la suite general, todos sobre bases sintéticas de host:

- `budget/budget_lifecycle_test.dart`, Android: timeout de 45 s al leer la
  revisión después de eliminar una partida (`budget_lifecycle_journey.dart:462`).
- `synchronization/local_recovery_journey_test.dart`, dos manuales y recuperación:
  timeout de 30 s, limpieza con archivo ocupado y aserción tardía tras el timeout.
- Mismo archivo, fallo de disco/rollback: canal de isolate SQLite cerrado al
  comenzar una transacción.
- `wealth/wealth_lifecycle_test.dart`, Windows: «La operación patrimonial SQLite
  no terminó» en la espera del formulario (`wealth_lifecycle_journey.dart:71`).

Los escenarios de presupuesto/recuperación ya aparecen en
[MA-TSK-235](../ep-028/verificacion-e2e.md); no se afirma igualdad exacta de causa
ni causalidad con esta corrección sin reproducirlos. Propietarios para seguimiento:
EP-011 MA-TSK-105, EP-006 MA-TSK-059 y EP-009 MA-TSK-077, con integración
EP-030 MA-TSK-253 si se confirma un defecto de producto. No se cambian sus motores
ni se amplían timeouts, y no se omiten casos para declarar verde el conjunto.

La repetición secuencial completa de esos tres archivos pasa sin cambios de
código entre ambas ejecuciones: no reproduce los cuatro fallos de la pasada
general. No basta para concluir su causa ni para dar por aprobada la calidad
general. Se conservan ambos resultados; no se repite toda la suite para obtener
un verde y no se atribuye un fallo financiero reproducible al paquete instalado.

El primer `pub get --enforce-lockfile` restringido falló al consultar advisories
en pub.dev. La primera regresión restringida no llegó al menú por bloqueo de
restauración/recuperación al abrir SQLite temporal. La repetición autorizada
reprodujo I01 y luego comprobó su corrección. No se atribuyen esos obstáculos
del entorno a pérdida financiera ni se modifican permisos permanentes.
Logs locales ignorados: `.tools/ma-tsk-250-pub.log`,
`ma-tsk-250-pending-before.log`, `ma-tsk-250-pending-baseline.log`,
`ma-tsk-250-pending-after.log`, `ma-tsk-250-quality.log` y
`ma-tsk-250-failures-isolated.log` y `ma-tsk-250-environment-*.log` en `.tools/`.

## Recorrido pendiente sobre el paquete real

Aplicar esta matriz solamente tras acreditar W01. Reutiliza
[datos y reposición T02](datos-sinteticos.md), [oráculos](oraculos.json),
[EP-001](../ep-001/casos-referencia.md) y
[EP-026 aprobado](../ep-026/prototipo/aprobacion.md). Los estados siguientes
se refieren al **paquete production instalado en PC físico**, todos sin ejecutar.
No repiten la matriz de instalación/actualización EP-028.

| Paso | Acción y contraste | Estado actual |
|---|---|---|
| P00 Identidad/aislamiento | Verificar entrega mediante `windows-delivery.mjs verify`; registrar hash del manifiesto, Setup y EXE instalado, versión/commit, APP_ENV=production, Windows, usuario/perfil aislado y referencia exacta a evidencia 235 del mismo candidato. Abrir desde su acceso instalado y comprobar ruta del proceso. Conservar versión previa y copias recuperables. | Bloqueado W01; sin evidencia 235 del mismo candidato. |
| P01 CSV nativo | Desde Gestión seleccionar los bytes T02 con el selector Windows, revisar preview y resolver cuenta/árbol; cancelar una revisión sin altas y luego confirmar 48 partidas/10 reales. Abrir historial y originales. Repetir mismos bytes renombrados: 0 altas, dos Café distintos. | Bloqueado W01. |
| P02 Categorización | Preservar BASE-T02; variante V01 añade dos pendientes (+7/−3). Acceder desde Gestión y desde lote; cancelar y confirmar individual/lote, revisar selección visible y desaparición de pendientes, procedencia/UUID y fotos intactas. V02 sin cuenta bloquea confirmación sin alta parcial. Reponer BASE entre variantes. | Bloqueado W01; I01 corregido solo en host. |
| P03 Openbank | Usar únicamente fixture fiel entregado por 129 con revisión/hash y oráculo aprobado; selector, cuenta, preview, confirmación, historial/originales, repetición y solapamientos. Contrastar fotos antes/después. | Bloqueado W01/W03; selector o mock no satisfacen el criterio. |
| P04 Presupuesto | Editar y guardar partidas desde mensual y anual; comprobar cero explícito/ausencia en desglose y reapertura. Intentar Vivienda padre con Alquiler existente (V07): rechazo completo, 48 partidas/+1100 enero intactos. | Bloqueado W01. |
| P05 Propuesta 2027 | V08 desde BASE: revisar 60 asignaciones, enero +3100/−1000/−360/−500/−20 y febrero +3020/−1000/−430/−500/0; marzo–diciembre cero editable por raíz. Cancelar deja 2027 vacío. Reabrir, editar Ocio enero a −30 antes de guardar; total previsto enero +1210 y anual +2300 EUR; desglosar y reabrir. Conservar 2026 y reponer BASE después. | Bloqueado W01. |
| P06 Fotos/liquidez | BASE enero: líquidos 9000/neto 14000, fecha 2026-01-01. Febrero V03 ausente; V04 incompleta con pendientes; V05 completa con ahorro cero → neto 11900/líquidos 6200/2,07 meses. Corregir principal a 6300 → neto 12000. Reponer V05 para V06: cartera líquida febrero → 16700/5,57, enero conserva 9000/3,00; corregir a media recupera 6200/2,07. Importación/categorización no cambian fotos. | Bloqueado W01. |
| P07 Consultas/retorno | BASE: Inicio/Estado enero +1229,75/+1100/+129,75; febrero +1099,90/+1100/−0,10. Patrimonio 14000; anual previsto +13200, real +2329,65; indicador 3,00 meses. Desplegar Alimentación hasta hoja sin doble conteo y Ocio con dos Café/−20. Diagnóstico y nuevo cálculo sin reparar ni escribir. Cambiar meses/año (V09), entrar a registros y volver conservando periodo/filtros. | Bloqueado W01. |
| P08 Ausencias/teclado/visual | V10 ingresos incompletos; V11 ingresos nulos; V12 líquidos cero → 0,00 meses. Recorrer Tab/Shift+Tab, Enter/Escape y foco tras selector, diálogos y retorno; redimensionar ventana y revisar frente a EP-026 sin recortes ni cambios de diseño. Registrar resolución/escala. | Bloqueado W01. |
| P09 Persistencia/evidencia | Cerrar proceso y reabrir desde el acceso instalado: mismas filas, UUID, revisión y resultados del estado guardado. Comparar copias/exportaciones mediante servicios existentes, conservando originales. Identificar cada captura/log por paso, fecha, candidato, origen «paquete production instalado/PC físico» y resultado esperado/observado. | Bloqueado W01. |

La edición P05 es una operación de ensayo sobre el caso H: sustituye únicamente
el −20 de Ocio enero por −30, delta −10 sobre total mensual +1220/anual +2310
de la propuesta sin editar; no cambia las reglas de propuesta ni el oráculo BASE.

Al recibir el candidato, contrastar hashes antes de reutilizar MA-TSK-235. Si
cambian los bytes o fuentes, revisar con EP-028 qué evidencia sigue siendo
aplicable; no atribuir la instalación de otra versión al nuevo EXE. Un fallo
reproducible de conexión/navegación se corrige con regresión aquí; una carencia
de dominio se devuelve al propietario de la [matriz T01](auditoria-cobertura.md).
No se completa T04 por documentar W01/W03, no se acepta MA-TSK-217 por tests y
EP-030 solo puede cerrarse tras expediente y aprobación humana explícita.
