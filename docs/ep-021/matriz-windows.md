# MA-TSK-168 · Matriz anual Windows

Ticket y dependencias consultados en Epic Board, tablero **My autofinance**,
el 2026-10-11. MA-TSK-166, MA-TSK-167 y MA-TSK-170 figuran completados;
la indicación de aprobación pendiente en el suplemento visual local es anterior
a ese estado y a la autorización de implementación facilitada por el usuario.
Se sigue el mockup MA-TSK-167 y EP-001 §3/§5.3/caso E.

## Integración y comportamiento

`createBudgetSource` incorpora `AnnualBudgetQuery`, sobre la misma SQLite,
árbol e invalidación de la sesión. `/presupuesto` presenta la matriz por
defecto; conserva el punto de inyección `AnnualBudgetBuilder` de MA-TSK-170.
La captura mensual sigue en `/presupuesto/mensual`. No hay nuevas tablas,
repositorios, reglas financieras ni motor de propuesta.

La matriz muestra categoría, doce meses y total anual, raíces inicialmente
contraídas y expansión hasta tres niveles. La consulta conserva todo el árbol
activo y las archivadas con datos/antecesores. La categoría queda fija al
desplazar las cifras; las cabeceras quedan fuera del scroll vertical del cuerpo.
Las barras y las flechas izquierda/derecha permiten desplazamiento horizontal,
sin exigir rueda. Los tamaños se adaptan al escalado de texto.

Una partida propia abre el campo dentro de su celda. Intro o la acción
**Confirmar celda** persiste exclusivamente esa partida; perder foco no guarda.
La creación/edición reutiliza `BudgetManagement` y `parseBudgetAmount` EP-011.
Cero conserva su UUID; un campo vacío es error, nunca borrado. Los errores
incluyen mes/ruta y, en conflictos, ambas rutas; conservan borrador y datos
anteriores. Durante la escritura se bloquean doble envío y salida. El éxito
solo se anuncia después de persistir y se releen los agregados.

Subtotales y totales abren los enlaces de partidas EP-019/MA-TSK-170, sin editar
el agregado. Una ausencia puede iniciar una partida; la persistencia rechaza
padre/descendiente sin sustituir ni desglosar datos. El formulario existente
permite intentar una alta propia desde el desglose de un subtotal, y explica
el conflicto. Las archivadas permiten corregir partidas existentes, no altas.
**Formulario / Eliminar partida** reutiliza el borrado explícito confirmado
EP-011. Una corrección solo cambia el importe; conserva UUID, concepto,
discrecionalidad, procedencia y fecha de creación. El borrado conserva la huella
de importación.

Windows estrecho usa tarjetas, total anual, mes enfocado y doce meses
desplegables; captura/corrección/borrado abre el formulario EP-011. Los totales
mensuales del resumen identifican su mes. Esta composición es el fallback de
Windows; MA-TSK-169 puede aportar su interfaz Android usando la inyección
existente, sin duplicar servicios.

Los controles de periodo, destinos, Gestión, enlaces, Escape, Atrás y cierre
usan protección de borrador. Una invalidación de categorías relee sin perderlo;
si una nueva jerarquía oculta su fila, el editor se presenta fuera de la matriz.
Una restauración cambia la identidad del origen y bloquea guardar el borrador
anterior. Las lecturas llevan una generación de petición para descartar
respuestas tardías. Una lectura fallida oculta cifras y permite reintentar.

El contexto EP-016 conserva expansiones en `abiertas`, scroll exterior en
`posicion`, y foco/scroll de matriz en el token opaco de `foco`
(`…|matrix=horizontal,vertical`). El retorno con pila conserva la instancia;
sin pila reconstruye las posiciones y el foco. No se añaden parámetros URL ni
se amplía el conjunto de orígenes admitidos por MA-TSK-170.

## Verificación

`test/budget/annual_budget_screen_test.dart`: **18 pruebas** con SQLite real de
archivo y datos sintéticos. Cubren árbol/totales, ausencias/neto cero, edición
con Intro, pérdida de foco, cero/vacío, doble envío, conflictos en ambos
sentidos, rollback/reintento, metadatos CSV, archivo, borrado confirmado,
protección de año/destino/Gestión/Escape/cierre, invalidación/restauración,
lecturas tardías, cambio de ancho/jerarquía, retorno sin pila y teclado.
Las regresiones históricas conservan el foco y la posición del origen anual
mientras la captura mensual secundaria cambia su contexto local. Cambiar el
mes enfocado anual reinicia las posiciones/foco, conservando las partidas.
El caso E presenta 48 UUID, doce totales de +1.100,00 EUR y +13.200,00 EUR
anuales, sin doble conteo. Anchos 320/840/1440 con texto al 200 % no provocan
desbordamientos Flutter.

Para capturas locales legibles en Windows:
en PowerShell, asignar `$env:ANNUAL_VISUAL_QA='1'` y ejecutar
`flutter test --no-pub --concurrency=1 test/budget/annual_budget_screen_test.dart`.
La variable es solo del comprobador; carga Segoe UI/Material Icons y guarda
PNG ignorados en `.tools/ma-tsk-168-*.png`. Se revisaron la matriz normal,
la matriz al 200 % y las tarjetas estrechas. No añade fuentes al producto.

La comprobación completa y las compilaciones finales se registran en
`.tools/ma-tsk-168-quality-verified.log`, `ma-tsk-168-windows-final.log` y
`ma-tsk-168-android-final.log`. Se usa Flutter 3.47.0/Dart 3.13.0 y el lockfile
fijado; los builds usan `APP_ENV=test` y `--no-pub`. La batería limita su
concurrencia a cuatro procesos mediante un wrapper temporal del comando;
el script de calidad no cambia.

`check-quality.ps1` pasa con **1.607 pruebas** y las cuatro variantes de
arranque. Después del último ajuste de los focos de Captura/Propuesta se
repite formato y análisis sin incidencias, además de **230 pruebas** de
presupuesto completo, navegación histórica/sesión/periodos y arquitectura;
evidencia en
`.tools/ma-tsk-168-affected-final.log`. Los builds finales corresponden a ese
mismo estado. La repetición evita solapar ejecutores que mantienen abierta
la DLL nativa de SQLite.

No se realizó recorrido E2E nativo en Windows/Android ni comprobación con
lector de pantalla. Las pruebas de widgets y builds no acreditan esas pruebas.
Los cambios de Drive/README/prototipos de otras épicas ya presentes quedan
fuera de la entrega, en la rama configurada `ticket/ma-tsk-113`, remoto `origin`.
La calidad del checkout incluye esos cambios concurrentes; no acredita una
clonación limpia hasta que su ticket publique también los archivos necesarios.
El HEAD previo `26f7f1a` ya importa `lib/app/drive_upload_factory.dart` desde
`drive_reconciliation_factory.dart`, y `domain/drive_upload.dart` desde los
consumidores de sincronización; ambos archivos permanecían sin seguimiento
al iniciar MA-TSK-168. Se conserva esa dependencia ajena sin incorporarla.
Este ticket no cierra EP-021 ni marca MA-TSK-169/172 como completados.
