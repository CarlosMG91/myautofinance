# MA-TSK-219 · Verificación y traspaso

Entrega contractual del 2026-10-16. Se utiliza el ticket completo facilitado
por el usuario; sin conector disponible, no se cambia el estado de Epic Board.

## Fuentes contrastadas

- [Reglas aprobadas EP-001](../ep-001/especificacion.md),
  [casos de referencia](../ep-001/casos-referencia.md) y
  [CSV de entrada histórico](../ep-001/contrato-csv.md).
- [Contrato privado EP-006](../ep-006/contrato-copias-locales.md) y
  [primitiva de captura EP-004](../ep-004/transacciones-copias.md).
- `lib/app/data/sqlite/schema.drift`, `schema_policy.dart`,
  `local_database_store.dart`, `sqlite_wealth_repository.dart`,
  `lib/core/persistence/local_database_format.dart` y
  `lib/features/wealth/domain/wealth_reading.dart`.
- [Fotos y estados de lectura](../ep-004/fotos-patrimoniales.md): una cabecera
  vacía es `absent` incluso con cero cuentas vigentes. Cabecera conservada y
  ausencia de valor son datos distintos.

El código declara esquema **8** y `applicationId=1095126595`; el contrato
privado histórico muestra ejemplos del esquema 6, que no se trasladan al nuevo
manifiesto. No se cambia ningún contrato, motor o catálogo de otras épicas.

## Referencias ejecutables

Ejecutar desde cualquier directorio con Node **22.20.0** o compatible que incluya
`node:sqlite` (en esa versión emite advertencia experimental):

```powershell
node docs/ep-027/verificar-contrato.mjs
```

No requiere paquetes npm, red, Flutter ni datos personales. Lee el esquema del
repositorio y crea una SQLite temporal sintética, insertando tablas antes de
índices/triggers como hace la ordenación de Drift. Cierra y vuelve a abrir la
imagen con SQLite estándar en solo lectura. No llama a un motor de snapshot ni
al restaurador. Retira únicamente su archivo y directorio temporal exclusivo.

Comprueba siete CSV, nueve archivos con hash y las doce tablas financieras del
esquema vigente. El diccionario dentro del ejemplo coincide byte por byte con
el normativo. El esquema JSON se comprueba con un evaluador de los keywords
usados en este documento; no se presenta como validador JSON Schema general.
Los ejemplos de datos se publican descomprimidos para facilitar su revisión.
El comprobador construye además un manifiesto portable de referencia a partir
de la SQLite sintética íntegra; no se distribuye una copia de instalación ni
se presenta el ejemplo como archivo generado por la app.

| Criterio | Evidencia comprobada |
|---|---|
| Dos modos y copia privada distintos | Kinds públicos válidos, privado/versión futura/campo de catálogo rechazados; portable con filtro rechazado |
| Diccionario y esquema | Columnas/orden/tipos/null de los siete CSV; campos de origen contrastados con `PRAGMA table_info`; versión leída del código |
| Coherencia | Identidad/revisión de `database_state`; `application_id`, `user_version`, `integrity_check` y `foreign_key_check` |
| Filtro temporal | Enero–marzo inclusivos: entra 1 enero y 31 marzo, quedan fuera 31 diciembre anterior y 1 abril; un solo mes, todo histórico y selección vacía 9999-12 |
| Contexto completo | Cuenta cerrada en 2025, categoría archivada sin uso y ancestros hasta tercer nivel; periodos históricos sin recortar |
| Ausencia y cero | Presupuesto cero, foto cero, presupuesto ausente, cabecera vacía `absent`, foto incompleta y mes sin cabecera; no hay columnas de subtotales |
| Signos | Mínimo/máximo int64 en movimientos, ingreso presupuestado negativo, deuda positiva; ninguna inversión histórica |
| Procedencia y texto | LEFT JOIN de lote/fila/ordinal para movimiento y presupuesto; manuales nulos; discrecionalidad vacía distinta de null |
| Precisión y CSV | Revisión int64 máxima, ordinal mayor que 2^53; mínimo int64 sin desbordar; `;`, comillas, CRLF/LF/CR, Unicode y conceptos `=`, `@`, `+` conservados contra SQLite |
| Manifiestos e integridad | Conteos lógicos, tamaño y SHA-256 real de cada archivo; alteración de byte detectada; ruta ajena, duplicado y tamaño cero rechazados |
| Copia íntegra | Tabla de originales incluida; cinco movimientos aunque el ejemplo CSV tenga tres; todas las tablas contabilizadas |

La prueba es de referencias contractuales y lectura de SQLite sintética, no de
una función de exportación integrada, ZIP producido por la aplicación ni
restauración de instalación. El esquema JSON y las restricciones semánticas
del contrato deben aplicarse juntos. La implementación futura tendrá que
comprobar también los ZIP, claves JSON duplicadas, límites de extracción,
cancelaciones y guardado en cada plataforma.

## Verificación del repositorio

- Flutter **3.47.0** / Dart **3.13.0**: `flutter --version` y
  `scripts/check-toolchain.ps1` correctos. `flutter pub get --enforce-lockfile`
  completado sin cambiar `pubspec.lock` ni actualizar SDK/paquetes.
- `scripts/check-quality.ps1`: formato de 480 archivos sin cambios y análisis
  estático sin incidencias. Suite terminada en 12:56: **1.961 pruebas superadas
  y tres fallidas**; el script termina con error y no ejecuta las cuatro
  variantes APP_ENV posteriores. La suite general encuentra un fallo en
  `test/drilldowns/report_drilldown_journey_test.dart`, caso
  `MA-TSK-194 tres informes SQLite: windows`: `Bad state: No element` al hacer
  `ensureVisible`, desde `test/support/report_drilldown_journey.dart:171`.
  Esos archivos y la implementación de la app no se modifican en T01.
  También fallan los dos casos de
  `test/movements/pending_lifecycle_test.dart` (Windows tabla y Android tarjetas),
  por el mismo `Bad state: No element` desde
  `test/support/pending_lifecycle_journey.dart:144`, igualmente sin cambios aquí.
- Se intenta contrastar el caso en una extracción aislada de `HEAD` anterior
  (`e62d631`). No se acredita el resultado del caso en esa base: la resolución
  offline genera la configuración, pero falla al crear enlaces de plugins
  Windows por falta de Developer Mode; la ejecución posterior con `--no-pub`
  falla al compilar por tipos ausentes `DriveUploader` / `DriveUploadResult`.
  El checkout compartido contiene cambios concurrentes de sincronización que
  no forman parte de este ticket. No se declara probado que el fallo de MA-TSK-194
  existiera en ese commit ni se incluye código concurrente para resolverlo.
- `node --check` y comprobador específico correctos. También se comprueban
  tamaño/SHA-256 de los nueve archivos leyendo sus bytes desde el índice Git,
  para detectar conversiones de fin de línea en la entrega. `git diff --check`
  correcto; el atributo CSV `cr-at-eol` reconoce el CRLF normativo.
- No se compilan plataformas ni se acredita ejecución de la exportación en
  dispositivos: solo cambian contrato, referencias sintéticas y comprobador.
  Las variantes APP_ENV posteriores a la suite de `check-quality` no se
  acreditan cuando esta falla.

## Traspaso

T02/T03 pueden implementar los dos exportadores contra este contrato,
reutilizando una única captura existente y sin tocar el catálogo privado.
T04 gestiona el guardado nativo. T07 debe documentar validación/extracción a
carpeta nueva Windows y consulta SQLite, también de copias hechas en Android.
T05 requiere aprobación explícita del mockup antes de UI T06. Esta entrega no
acredita aprobación visual ni ejecución real de las dos acciones en
Windows/Android: ambas y la lectura independiente de artefactos de la app
pertenecen a T08 al cierre de épica. No se bloquea por EP-025 ni se modifica.

La regla local de atributos conserva bytes exactos del diccionario y ejemplos
hasheados, incluidos saltos internos, al hacer checkout en Windows u otro sistema.
El resto de cambios concurrentes del checkout queda fuera de esta entrega.
