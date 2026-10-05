# MA-TSK-103 · Captura y detalle Android

Se consultó Epic Board mediante `GET http://localhost:4310/api/data`, tablero
**My autofinance**, con workspace coincidente. MA-TSK-103 está en curso;
MA-TSK-100 y MA-TSK-101 están completados. MA-TSK-099 está completado con
`approvedAt: 2026-10-05T11:30:53.008Z` y mockup aprobado
<http://localhost:4310/mockups/autofinance-ma-tsk-099-v1.html>.
Esta aprobación posterior prevalece sobre el estado pendiente del documento
original de propuesta. No se cambia el estado del tablero.

## Implementación

Se completa el formulario compartido entregado por MA-TSK-102, sin añadir
otra persistencia ni alterar contratos financieros, rutas o selector común.
Las tarjetas del mes abren alta o detalle en rutas secundarias; el detalle
entra en lectura y ofrece Editar. La captura requiere año/mes, categoría por
UUID con ruta completa e importe firmado en EUR; no hay campo cuenta.
Guardar partida o confirmar desde el teclado persiste los tres campos.
Cero es una partida y el campo vacío da error. La navegación conserva el
mes de origen y ofrece Ver mes tras una corrección a otro periodo.

`BudgetManagement` preserva concepto, discrecionalidad, ID y procedencia CSV.
El selector reutilizado solo ofrece categorías activas; una partida histórica
archivada puede mantener su categoría al corregirse. Los conflictos muestran
mes y ambas rutas, preservan el borrador y rechazan sin sustituir partidas.
Las escrituras se bloquean mientras hay una operación pendiente, y un fallo
puede reintentarse conservando entradas. Antes de escribir se verifica la
identidad de la conexión local para proteger borradores tras una restauración.

Cancelar, Atrás de Android y los destinos protegen las entradas con el diálogo
Seguir editando / Descartar cambios. Eliminar requiere confirmación y muestra
los datos de la partida **guardada**, incluso si el borrador cambió categoría.
Un fallo de borrado conserva partida y borrador; volver a Eliminar partida
pide otra confirmación. El botón Reintentar del guardado se reserva para un
fallo de guardado, evitando confundir estas dos operaciones.

El formulario aplica objetivos táctiles mínimos de 48 × 48, título de hasta
dos líneas con altura que admite texto ampliado, ayuda y errores multilínea
y contenido desplazable. Las etiquetas permanecen visibles y los errores
usan regiones semánticas de anuncio. No se añaden dependencias ni migraciones.

## Verificación

Flutter 3.47.0 / Dart 3.13.0 y `check-toolchain.ps1` correctos. Dependencias
resueltas con `--enforce-lockfile`, sin cambios de SDK ni lockfile. El intento
inicial de acceso a pub.dev dentro del sandbox falló; la resolución offline
con caché funcionó y la comprobación general se ejecutó con acceso de red.

Nueve pruebas específicas en `test/budget/budget_android_form_test.dart`
usan composición de rutas real, tema Android y SQLite de archivo sintético:

- Alta desde selector, nombres repetidos diferenciados por UUID/ruta, cero,
  confirmación explícita, objetivos táctiles y cierre/reapertura de SQLite.
- Mes e importe inválidos, cancelación del selector y borrador conservado.
- Conflictos padre-descendiente en ambos órdenes y cambio a un mes válido.
- Fallo SQLite mediante trigger, rollback, doble toque y reintento sin duplicar.
- Corrección de histórico archivado y cambio posterior de los tres campos,
  conservando lote, fila, ordinal, concepto y discrecionalidad de una importación.
- Atrás Android, cancelar y cambio de destino con protección del borrador.
- Borrado cancelado, confirmado, fallido y repetido, con su categoría guardada.
- Lectura fallida con reintento y sustitución de base que bloquea la escritura.

Los recorridos de alta, validación, detalle archivado y borrado se ejercitan a
320 px y texto 200 %, sin excepciones de layout. Estas pruebas de widgets en
el host no acreditan uso en Android físico, TalkBack ni teclado del sistema.
Se renderizaron y revisaron además capturas de alta y validación a ese ancho
y escala, usando Segoe UI en el host; las capturas locales quedan en `.tools`
y no se incorporan al repositorio.

- `scripts/check-quality.ps1`: formato, análisis sin incidencias, 1.036 pruebas
  generales y las cuatro variantes de `APP_ENV` correctos. La batería incluye
  los nueve recorridos nuevos y las regresiones del formulario Windows.
  Hay un aviso de toque fuera de pantalla en una prueba previa de navegación
  de patrimonio; no pertenece a este ticket y esa prueba termina correctamente.
- Windows release y Android debug, `--no-pub` y `APP_ENV=test`: correctos.
  Windows necesitó ejecutar MSBuild fuera del sandbox. Android utilizó JDK 17
  con selección temporal de Flutter, restaurada al terminar.
- `git diff --check` de los archivos propios: correcto.

Los cambios concurrentes de sincronización, README y prototipos de categorías
se excluyen del commit.
