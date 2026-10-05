# MA-TSK-094 · Lotes y navegación de Movimientos

## Evidencia y alcance

Ticket consultado el 2026-10-05 mediante `GET http://localhost:4310/api/data`,
tablero **My autofinance**. MA-TSK-090/092/093 y los requisitos externos
MA-TSK-084, MA-TSK-071/072 constan terminados. MA-TSK-091 contiene aprobación
humana de **Tú** del mockup complementario, registrada el 2026-10-05:
«Propuesta visual aceptada: http://localhost:4310/mockups/autofinance-ma-tsk-091-v1.html».
Se reutilizan EP-001, la entrega visual EP-002, la arquitectura EP-003,
SQLite/transacciones EP-004, selector EP-008 y catálogo de cuentas EP-009.

No se modifican tablas, repositorios, operaciones financieras ni sincronización.
Los documentos y cambios concurrentes de otros tickets quedan fuera del commit.
La épica conserva MA-TSK-095 pendiente; esta entrega no la cierra.

## Operaciones de la lista

`MovementListSource` incorpora el servicio `MovementManagement` de MA-TSK-090
y una identidad opaca de conexión, inyectados por `createMovementListSource`.
`LocalBackupSession.movements` continúa resolviendo la conexión activa por visita.

- Selección explícita y página visible capturan UUID concretos en un
  `MovementBatchRequest` inmutable, con el contexto de consulta y la identidad
  de la base leída. Nunca se envían filtros al caso de uso de escritura ni se
  amplía el lote a resultados ocultos.
- Asignar abre el selector compartido de MA-TSK-084 y confirma cantidad,
  UUID, periodo y ruta de destino. Crear una categoría es una acción explícita
  independiente dentro del selector. Cancelar el selector o la confirmación
  no escribe movimientos y conserva la selección.
- Quitar categoría usa `removeCategory` únicamente sobre los UUID capturados.
  Borrar seleccionados confirma cantidad, UUID, periodo y conservación de
  procedencia, con diálogo desplazable. Cancelar, Escape y Atrás no escriben.
- Durante selector, confirmación y escritura quedan bloqueados filtros,
  selección, paginación, entradas al editor y navegación de la lista. Un
  segundo envío no inicia otro lote.
- Los repositorios existentes revalidan todos los UUID y la categoría dentro
  de la transacción. Los rechazos muestran el fallo en una región accesible,
  mantienen selección y no anuncian éxito. No se omiten filas inválidas.
- El resultado se anuncia únicamente cuando el servicio devuelve el commit.
  Se refrescan consulta, etiquetas y subtotal firmado. La selección se cruza
  con los resultados visibles; el borrado retira los UUID eliminados antes de
  releer y reinicia la paginación. Si falla la lectura posterior, el éxito
  confirmado sigue visible y se ofrece reintentar la lectura sin repetir el lote.

## Protección ante restauración

Antes de escribir se vuelve a resolver la fuente. Una identidad distinta de
la capturada rechaza el lote con selección intacta y exige releer/seleccionar.
La relectura de una conexión nueva limpia la selección anterior y reinicia
la paginación, sin reutilizar cursores de la imagen sustituida. No basta
comparar `dataset_id` y revisión: restaurar la misma copia también reemplaza
la conexión y puede reproducir ambos valores.

El formulario registra asimismo la identidad de su lectura y la contrasta
antes de alta, edición o borrado. Ante reemplazo conserva el borrador y exige
volver a abrir el movimiento. Los cambios posteriores a esta comprobación
siguen protegidos por la conexión elegida: la primitiva existente de EP-006
bloquea nuevas escrituras, drena las admitidas antes del intercambio y cierra
la conexión anterior. Ninguna operación se redirige silenciosamente a la base
restaurada. No se introduce sincronización automática ni una conexión aparte.

## Contrato público y enlaces para futuros informes

`features/movements/movements.dart` exporta `MovementListQuery`, sin Flutter
ni dependencia de Patrimonio. Campos:

| Campo | Significado |
|---|---|
| `from`, `until` | Fechas civiles; inicio incluido y fin exclusivo. `until=null` solo para el final del calendario, año 9999. |
| `accountId` | UUID de cuenta opcional; ausente incluye todas. |
| `categoryId` | UUID estable del nodo, opcional; nunca el nombre visible. |
| `scope` | `branch` incluye descendientes actuales; `direct` solo referencias directas. |
| `unclassified` | Solo categoría NULL; incompatible con `categoryId`. |
| `concept` | Búsqueda por concepto, opcional, con la normalización de MA-TSK-088. |

Los informes reciben por constructor un callback como
`void Function(MovementListQuery) onOpenMovements`. La composición en `app`
conecta ese callback con `MovementLinks.list(query, origin: currentRoute)` y
`Navigator.pushNamed`; no deben importar controladores ni pantallas internas
de Movimientos. EP-003 permite `monthly_status` y `actual_spending` consumir
esta entrada pública. Otros consumidores necesitan revisar su dependencia.

`app/navigation/movement_links.dart` entrega `list`, `create`, `detail`,
`management`, `parse` y `origin`. `create` abre `/movimientos/nuevo` y `detail`
valida el UUID para `/movimientos/:id`; ambos conservan el mismo contexto.

```dart
final query = MovementListQuery(
  from: ValueDate(2026, 3, 1),
  until: ValueDate(2026, 4, 1),
  categoryId: categoryId,
  scope: MovementCategoryScope.branch,
);
Navigator.of(context).pushNamed(
  MovementLinks.list(query, origin: '/estado?a=2026&m=03'),
);
```

Serialización canónica de la lista:
`/movimientos?desde=AAAA-MM-DD&hasta=AAAA-MM-DD&rama=UUID&alcance=rama&origen=…`.
`rama=sin-clasificar` representa NULL; `alcance=directo` restringe al nodo.
`cuenta` y `concepto` conservan esos filtros si se suministran. `Uri` codifica
la búsqueda y el origen, incluidos sus propios parámetros. El origen admite
solo rutas internas del índice y los cinco destinos existentes, conservando
sus parámetros; no admite URLs externas.

Se aceptan también `a=AAAA&m=MM`, y los alias entregados por MA-TSK-092:
`c=UUID`, `alcance=branch/direct`, `sinClasificar=1`. Se rechazan periodos,
alcances, UUID y parámetros de categoría ambiguos antes de consultar SQLite.
Los enlaces desde Gestión transmiten exclusivamente el mes de trabajo; no
heredan filtros del informe. La entrada desde informe transmite su consulta
explícita. Todas las lecturas mantienen recientes primero y desempate por UUID.

La pila conserva consulta, selección y estado de la lista al abrir nuevo o
detalle. El origen y la consulta quedan disponibles también para retorno sin
pila: lista → informe, editor → lista. Se conservan las entradas Gestión de
Categorías, Fichas, Drive y Copias locales. No se implementan vistas de informes.

## Verificación

Pruebas nuevas: `test/movements/movement_integration_test.dart` y
`test/movements/movement_links_test.dart`. Usan exclusivamente datos sintéticos,
SQLite real y los adaptadores existentes. Cubren selección exacta/página,
preservación de campos, subtotal al salir de un filtro, cancelación, rechazo
por UUID ausente/categoría archivada, rollback en las tres acciones, espera
de escritura/doble envío, selector compartido, Gestión, enlaces y retorno de
detalle. Borrado a 320/412/1440 px con texto al 200 %, Escape y Atrás.

Las pruebas de restauración usan copias locales reales, incluida restauración
de la misma identidad y revisión. Comprueban rechazo del lote anterior y del
formulario con borrador, seguido de relectura y nueva selección válidas.
MA-TSK-090 conserva la cobertura de procedencia importada, presupuestos, fotos
y fallos de commit; se ejecuta también como regresión, sin recrear importadores.

Resultados del entorno local:

- Flutter 3.47.0 / Dart 3.13.0, `check-toolchain.ps1` y resolución con
  `--enforce-lockfile` correctos. SDK Flutter, toolchain y lockfile sin cambios.
- Las 115 pruebas dirigidas iniciales de Movimientos/categorías, navegación
  y arquitectura pasan. Las 19 de lotes/enlaces finales y las 29 de integración,
  lista y arquitectura tras añadir invalidación del cursor también pasan.
- El comprobador EP-001 termina con `OK`; `git diff --cached --check` correcto.
- Windows release `--no-pub --dart-define=APP_ENV=test` compila correctamente,
  también en la recompilación final (72 segundos).
- Android debug con las mismas opciones compila correctamente (208,8 segundos).
  Se usa Temurin 17 temporal en `.tools`, descargado de Adoptium y comprobado
  por SHA-256. El proceso Gradle confirma `javaVersion=17`; se fuerza únicamente
  para el comando con `GRADLE_OPTS=-Dorg.gradle.java.home=<ruta-JDK-17>`, sin
  cambiar la configuración global. Salidas habituales en `build/windows/` y
  `build/app/outputs/flutter-apk/app-debug.apk`, excluidas del repositorio.
- La primera ejecución de `check-quality.ps1` pasa con 1.000 pruebas y las
  cuatro variantes APP_ENV. Una segunda, durante compilaciones, termina con
  998 correctas y dos fallidas del recorrido existente de recuperación:
  timeout de 30 segundos seguido de fallo por conexión cerrada. No se modifica
  ese servicio, su prueba ni sus límites para ocultar el fallo. La comprobación
  de entrega final, sin builds simultáneos, pasa formato, análisis sin incidencias,
  las 1.000 pruebas (incluidos esos casos, con sus límites originales) y las
  cuatro variantes APP_ENV: development/test/production/invalid-synthetic.

No se acredita un recorrido manual con dispositivos, lector de pantalla ni
Drive real. La suite general corresponde al checkout de trabajo, que conserva
también cambios concurrentes ajenos; únicamente los 14 archivos propios de
MA-TSK-094 se confirman y publican en la rama configurada `ticket/ma-tsk-071`.
