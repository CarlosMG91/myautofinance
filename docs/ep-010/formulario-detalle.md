# MA-TSK-093 · Detalle, formulario y borrado individual

Implementación del 2026-10-05. Se consultó `GET /api/data` de Epic Board,
tablero **My autofinance**: MA-TSK-089, MA-TSK-091, MA-TSK-084 y
MA-TSK-071/072 constan `done`. MA-TSK-091 contiene la aprobación humana
de **Tú**: «Propuesta visual aceptada:
http://localhost:4310/mockups/autofinance-ma-tsk-091-v1.html».
Esta evidencia supera el estado pendiente del documento local de propuesta;
no se modifica ese trabajo de otro ticket.

## Implementación

- `/movimientos/nuevo` y `/movimientos/:id` usan el caso de uso individual
  MA-TSK-089 con los repositorios y la unidad de trabajo SQLite existentes.
  La composición resuelve la conexión activa de la sesión al leer o guardar.
  No se crean tablas, conexiones independientes, importadores ni servicios
  simulados. El alta no preselecciona ni crea cuentas implícitamente.
- Detalle con identidad, fecha, concepto, cuenta, ruta actual de categoría,
  EUR firmado exacto, discrecionalidad, fila y lote de procedencia. Editar
  conserva identidad y procedencia. Discrecionalidad vacía la retira;
  «Quitar categoría» retira explícitamente la referencia.
- Se reutiliza `CategorySelector`, incluida creación explícita y cancelación.
  Una categoría archivada histórica se presenta y se puede conservar;
  las nuevas asignaciones solo ofrecen categorías activas. La persistencia
  vuelve a comprobar las referencias, también si se archivan tras elegirlas.
- El catálogo propietario de EP-009 se proyecta por UUID, nombre y vigencia
  inclusiva. Solo ofrece cuentas corrientes vigentes en el mes de la fecha
  introducida. Una referencia histórica no elegible se muestra deshabilitada.
  Sin opciones se explica Gestión → Fichas y la posibilidad de cambiar fecha.
  Movimientos no importa patrimonio; la proyección se compone en `app`.
- Validación junto a campos y foco en el primer error; fechas civiles,
  concepto obligatorio e importes exactos no cero. Un fallo conserva el
  borrador y permite reintentar. Guardar y borrar se bloquean durante la
  petición; el éxito solo se anuncia después de persistir.
- Borrar desde detalle confirma **1 movimiento**, concepto y UUID. Cancelar,
  Esc o Atrás no escriben. Un error mantiene detalle y permite reintentar;
  confirmar elimina y vuelve a la lista, que refresca el contexto existente.
- Salir con cambios mediante Volver, Cancelar, Esc, Atrás, pestaña o Gestión
  pide «Seguir editando» / «Descartar cambios». La solicitud de cierre de
  aplicación usa `AppLifecycleListener` y la misma confirmación. Cancelar
  edición retorna al detalle; abandonar retorna al origen. Durante escrituras
  no se permite salir. No puede proteger frente a terminación forzada del SO.
- La pila de navegación conserva filtros, periodo, página, selección, scroll
  y foco de la lista. Guardar fuera del mes devuelve al origen con aviso y
  «Ver mes». Parámetros inválidos o UUID inexistentes muestran recuperación
  sin escribir. Sin pila de origen, volver abre Estado del mes actual.
- Formulario en una columna, lateral 200/216 en PC, cinco destinos con
  etiquetas en ventana estrecha, márgenes 16/24/32 y contenido desplazable.
  Diálogos desplazables, foco inicial en título y retorno al disparador.
  El contexto de navegación de categorías se ha extraído y reexportado para
  reutilizar el selector sin introducir ciclos ni cambiar su contrato.

## Verificación

Las pruebas usan exclusivamente datos sintéticos y SQLite real. Cubren alta,
validación y borrador, espera de persistencia y doble envío, edición histórica,
retirada de categoría/discrecionalidad, procedencia importada, rechazo SQLite
de referencias obsoletas, fallos y reintento, confirmación de borrado,
Esc/Atrás, cierre solicitado, rutas inválidas y guardado fuera del mes con
retorno y «Ver mes». La adaptación se comprueba a 320/412/1024/1440 px con
texto al 200 %. También se comprueban selector, lista y arquitectura.

- Flutter 3.47.0 / Dart 3.13.0, `check-toolchain.ps1` y resolución con
  `--enforce-lockfile` correctos. SDK, toolchain y lockfile sin cambios.
- Análisis sin incidencias; 28 pruebas dirigidas finales de formulario,
  selector y arquitectura correctas. Las pruebas de lista también pasan.
  `node docs/ep-001/verificar-casos.mjs` y comprobación del diff correctos.
- `check-quality.ps1` se ejecutó dos veces. Formato y análisis pasan.
  La primera suite se interrumpió tras timeouts de recuperación; la segunda
  terminó con **977 pruebas correctas y cuatro fallidas**, en recorridos
  existentes de Drive/recuperación con límite de 30 segundos y errores
  posteriores de cierre. No se acredita ese comando global en verde.
  Los ocho casos de recuperación pasan por separado. Los cuatro fallos de
  la segunda suite pasan al repetirlos con `--timeout=2m` y el mismo código,
  sin modificar pruebas, servicios concurrentes ni política de CI.
- Las cuatro variantes de arranque `APP_ENV` (development/test/production/
  invalid-synthetic) pasan. Windows release con `--no-pub` y `APP_ENV=test`
  compila correctamente, también tras los ajustes finales de navegación.
- Android debug se intentó: bloqueado por **Android SDK no configurado**.
  No se acredita Android físico, lector de pantalla ni cierre nativo de Windows.

Solo se publican los archivos propios de MA-TSK-093 en la rama configurada
`ticket/ma-tsk-071`. Se excluyen README, cambios concurrentes de Drive y los
contratos/prototipos sin seguimiento de otros tickets. No se cierra la épica
ni se publican cambios restantes de tickets ajenos.
