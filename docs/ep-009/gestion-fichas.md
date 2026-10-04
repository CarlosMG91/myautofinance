# MA-TSK-072 · Gestión de fichas

Gestión → Fichas utiliza las rutas existentes de catálogo, alta y detalle.
El catálogo muestra todas las identidades, incluidas altas futuras y bajas,
con nombre, tipo y vigencia inclusiva. A partir de 840 unidades usa tabla;
en anchos menores usa tarjetas. El detalle conserva el historial de liquidez.

El alta distingue cuenta corriente, cartera agregada y deuda. Exige nombre,
mes de alta y liquidez explícita para activos; deuda no admite liquidez.
El mes de baja es opcional y no puede preceder al alta. Los meses se introducen
como AAAA-MM y se convierten al contrato Month del día 1.

La edición modifica nombre y permite dar de baja. Tipo y alta se muestran
en lectura; una ficha cerrada conserva su baja y permite cambiar su nombre.
La confirmación de baja explica su último mes incluido y la conservación de
referencias. No se añade borrado ni reapertura. No se implementan cambios de
liquidez: su gestión por mes corresponde al siguiente ticket.

WealthManagement coordina las operaciones existentes de AccountRepository
en la unidad de trabajo compartida. Nombre y baja se confirman juntos: si la
baja es incompatible con movimientos o fotos, el repositorio rechaza la
operación y el formulario conserva el borrador y explica la causa. No cambia
el esquema, migraciones, contratos de vigencia ni repositorios SQLite.
Cada escritura resuelve de nuevo el cargador de la sesión, también tras una
restauración. El éxito se anuncia después de finalizar la persistencia.

Cancelar, Volver, Escape y Atrás protegen los cambios sin guardar con
«Seguir editando» / «Descartar cambios». Los controles tienen etiquetas,
recorrido de foco y errores anunciados; la validación enfoca el primer campo
incorrecto. Los diálogos conservan el foco dentro y lo devuelven al control
de origen. Durante una escritura se bloquean las acciones incompatibles.
El catálogo se refresca al regresar, manteniendo en la pila el origen.

## Verificación

Datos exclusivamente sintéticos. Pruebas nuevas: tres tipos, liquidez de deuda,
vigencia inicial/final inclusiva, altas inválidas sin mutaciones, identidad
independiente con nombres iguales, rechazo de baja con foto posterior,
nombre/historial/revisión intactos tras rechazo, cierre y renombrado sin
reutilización; validación y foco, guardado pendiente sin éxito anticipado,
cancelación y Escape, recorrido Gestión/detalle/edición/catálogo y layouts de
320, 840 y 1440 unidades con texto al 200 % sin errores de overflow.

Resultado local del 2026-10-04: scripts/check-quality.ps1 correcto con
Flutter 3.47.0/Dart 3.13.0, resolución con --enforce-lockfile, formato sin
cambios, análisis sin incidencias, 864 pruebas y las cuatro variantes de
APP_ENV. git diff --check correcto. Las pruebas con SQLite en archivo se
ejecutaron fuera del aislamiento por la restricción de sus bloqueos de
recuperación, como en MA-TSK-071. pubspec.lock no cambia.
No se han realizado recorridos en Windows o Android físicos, lector de pantalla
ni revisión visual manual. No se ejecutan builds de plataformas: este ticket
solo cambia Dart y widgets, sin configuración nativa. Toolchain y lockfile
se conservan.

Se ha utilizado el ticket completo facilitado por el usuario. Epic Board no
está disponible en la sesión; no se ha actualizado su estado. La entrega
incluye únicamente los archivos propios de MA-TSK-072 y respeta los cambios
concurrentes de Drive y categorías.
