# MA-TSK-071 · Composición de Patrimonio

## Entradas y persistencia

`features/wealth/wealth.dart` publica `WealthManagement`, `AccountDetails`,
`WealthController` y `WealthManagementLoader`, junto con los puertos existentes
`AccountRepository` y `WealthRepository`. El grafo de funcionalidades no cambia:
Patrimonio no depende de movimientos, indicadores ni sincronización.

`app/wealth_management_factory.dart` inyecta `SqliteAccountRepository`,
`SqliteWealthRepository` y la unidad de trabajo con una misma conexión abierta.
`LocalBackupSession.wealth()` compone sobre la base de la sesión, resuelta por
el store después de recuperar cualquier restauración interrumpida. El controlador
resuelve este cargador en cada consulta; no retiene una conexión reemplazada al
restaurar. No se añaden bases, esquema, migraciones ni persistencia del prototipo.

Ejemplo para los controladores de los siguientes tickets:

```dart
final controller = WealthController(loadManagement: session.wealth);
final catalog = await controller.catalog();
final details = await controller.details(accountId);
final photo = await controller.month(Month(2026, 1));
final photos = await controller.year(2026);
```

El único puerto ampliado es `AccountRepository.list()`: devuelve todas las
fichas, incluidas las cerradas y las de alta futura, ordenadas por nombre e ID.
Dos fichas pueden compartir nombre y siguen siendo identidades distintas.
Su liquidez es null porque el catálogo no representa un mes. `listForMonth`
mantiene su filtro de vigencia y clasificación efectiva; `get` e `history`
conservan acceso a las bajas. `WealthManagement.details` consulta ficha e
historial de liquidez en una sola unidad de trabajo y rechaza IDs inexistentes.
Estas lecturas no modifican la revisión de datos.

Las operaciones de escritura de los futuros formularios se reciben en
`WealthManagement.accounts` y `.photos`, que son los puertos originales de
EP-004. La composición no duplica sus validaciones, reglas de vigencia,
transacciones ni semántica de foto parcial.

## Rutas preparadas

Se revisaron la aprobación de MA-TSK-019 registrada en
`docs/ep-002/entrega-flutter.md`, sus rutas y estados de foto/fichas, y los
recorridos de Patrimonio y foto de `mockup-final.html`. Se mantienen:

- `/patrimonio?a&m` y `/patrimonio/foto?a&m` consultan la foto del mes.
- `/patrimonio/fichas` consulta el catálogo completo desde Gestión → Fichas.
- `/patrimonio/fichas/:id` consulta la identidad y su histórico de liquidez.
- `/patrimonio/fichas/nueva` queda reservada para el formulario del siguiente ticket.

`WealthRoute` valida periodo y forma de ruta antes de consultar. El periodo por
defecto usa Europe/Madrid. `RouteSettings` conserva nombre, parámetros y
argumentos; la pila conserva el origen y su periodo al volver de catálogo y
detalle. El host actual solo expone consultas y estados de ausencia/completitud;
no escribe ni anuncia guardados. Una ruta inválida o una ficha inexistente
muestra «No se pudo abrir este detalle». La guardia existente de recuperación
también protege estas rutas.

Este ticket prepara composición y navegación. Los formularios de alta/edición,
liquidez y foto, los totales y la presentación financiera completa pertenecen
a los siguientes tickets de EP-009. No se redefine el mockup ni se añaden
indicadores, importación o Drive.

## Verificación

Datos exclusivamente sintéticos. Las pruebas nuevas en `test/wealth` comprueban:
catálogo con bajas, altas futuras y nombres repetidos; identidad e historial
tras reapertura; liquidez efectiva de la foto; cero registrado, foto parcial y
doce meses independientes; revisión intacta tras consultas; controlador creado
antes de restaurar que consulta la base restaurada; rutas válidas e inválidas;
mes de Madrid; Gestión, detalle cerrado y retorno; errores sin escrituras.

Resultado local del 2026-10-04: `scripts/check-quality.ps1` correcto con Flutter
3.47.0/Dart 3.13.0, resolución con `--enforce-lockfile`, formato, análisis sin
incidencias, 858 pruebas y las cuatro variantes adicionales de `APP_ENV`.
`pubspec.lock` no cambia. Las pruebas SQLite se ejecutaron fuera del aislamiento
porque este impedía abrir los bloqueos de recuperación incluso en pruebas
existentes. No se realizaron builds ni recorridos en dispositivos Windows o
Android: no hay cambios nativos y la evidencia es automatizada con SQLite en
archivo y widgets, no una verificación visual de las futuras pantallas.

Se utiliza el ticket completo facilitado por el usuario. No hay herramienta
Epic Board disponible en esta sesión y no se ha actualizado el tablero.
Los cambios previos de otros tickets se conservan fuera de esta entrega.
No se integra ni se hace push a la rama del tablero: entrega local para el coordinador.
