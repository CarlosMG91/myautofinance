# MA-TSK-102 · Edición del presupuesto mensual en Windows

## Diseño y composición

Se consultó `GET http://localhost:4310/api/data` de Epic Board, tablero
**My autofinance**, con workspace coincidente. MA-TSK-102 está en curso y
MA-TSK-099 está completado con `approvedAt: 2026-10-05T11:30:53.008Z` y
el mockup `http://localhost:4310/mockups/autofinance-ma-tsk-099-v1.html`.
Esta evidencia posterior satisface la aprobación que la propuesta local
todavía describe como pendiente. No se modifica el estado del tablero.

`/presupuesto?a=2026&m=01` compone el árbol mensual completo, los importes
propios y los subtotales de rama de solo lectura. Las categorías archivadas
con partida aparecen separadas y se incluyen una sola vez en el total.
Las sumas de presentación usan enteros de precisión arbitraria para evitar
desbordar al agregar varios importes int64. Se mantienen signos y formato EUR
español, y se distinguen ausencia y cero explícito.

La sesión resuelve la conexión SQLite vigente mediante `BudgetLoader`;
`createBudgetSource` inyecta lectura, gestión segura e invalidación categorial
existentes. Se comprueba la identidad de conexión antes de escribir para
impedir aplicar un borrador leído antes de una restauración sobre otra base.
No se modifica el esquema ni los contratos financieros.

Los únicos cambios compartidos son la inyección en `AutofinanceApp`,
`LocalBackupSession` y el despacho de presupuesto en `AppRouter`.
Se reutiliza `selectCategory` de EP-010/EP-008, sin modificar sus archivos,
los cinco destinos ni sus rutas. Gestión mantiene las cuatro entradas;
Importar CSV sigue sin habilitarse mientras no exista su pantalla.

## Interacción

- Pulsar un importe propio abre la edición; Intro o Confirmar celda persiste
  exclusivamente esa partida. Perder foco no escribe. No existe guardado
  del mes en bloque. El éxito aparece después de la escritura confirmada.
- Sin partida permite alta, incluido cero. Vacío, tres decimales o fuera del
  rango int64 rechazan la entrada y no eliminan nada.
- `/presupuesto/partidas/nueva` y `/presupuesto/partidas/:id` son secundarias.
  El detalle ofrece Editar, cambio de año/mes, categoría e importe; conserva
  ID, concepto, discrecionalidad, lote y fila CSV mediante `BudgetManagement`.
  Cambiar de mes vuelve al origen y ofrece Ver mes.
- Eliminar partida exige confirmación verbal. Cancelar/Esc conserva la
  partida; confirmar vuelve al mes con Sin presupuesto.
- Conflictos muestran mes y ambas rutas, sin sustituciones ni redistribución.
  El error conserva el borrador y ofrece Reintentar. Un fallo de relectura
  posterior al commit no transforma la operación confirmada en otra alta.
- Cambiar mes, destino, editor, Gestión, cancelar o salir con cambios exige
  Seguir editando / Descartar cambios. Cierre nativo se protege también cuando
  hay un diálogo abierto. Durante escritura se bloquean acciones incompatibles.
- La pila conserva el mes y el desplazamiento; al volver se relee y restaura
  el foco. Diálogos con foco inicial en título, navegación modal y Esc
  conservador; regiones semánticas para resultado/error y etiquetas de cifra,
  ruta, periodo y alcance. A menos de 840 px se usan tarjetas y formulario,
  también al estrechar Windows; cambiar tamaño conserva el editor abierto.

## Verificación (2026-10-05)

Flutter 3.47.0 / Dart 3.13.0, `check-toolchain.ps1` correcto y dependencias
resueltas con `--enforce-lockfile`, sin cambiar SDK ni lockfile.

- `scripts/check-quality.ps1`: formato, análisis, 1.025 pruebas generales
  y cuatro variantes de `APP_ENV` correctos. Después de añadir las dos últimas
  pruebas y reforzar la protección del cierre con diálogo abierto se repitieron
  formato, análisis y las 27 pruebas de presupuesto/arquitectura: correctos.
- Diez pruebas nuevas cubren formato y límites, celda individual, cero,
  pérdida de foco, vacío, conflictos, rollback SQLite mediante trigger,
  reintento sin duplicados, navegación/Gestión y borrador, cambio de
  mes/categoría/importe, metadatos, borrado confirmado, lectura fallida,
  cierre nativo y retorno de foco, histórico archivado y reapertura en archivo.
- Layout sin excepciones a 1440 px, 1024 px con texto 200 % y 320 px con
  texto 200 %. La vista estrecha permite guardar desde el formulario.
- Builds Windows release y Android debug con `APP_ENV=test`, sin pub:
  correctos. Android se verifica con el JDK 17 disponible en `.tools` mediante
  una selección temporal de Flutter, restablecida al terminar.
- `git diff --check` en los archivos propios: correcto.

Las pruebas de widgets ejecutan Flutter sobre el host y SQLite real, incluida
una base sintética de archivo cerrada y reabierta. No acreditan ejecución
interactiva nativa, lector de pantalla, alto contraste del sistema ni Android
físico: esas comprobaciones manuales permanecen sin verificar.
Los cambios concurrentes de sincronización, README y prototipos de categorías
se excluyen del commit de este ticket.
